data {
#include /data/data.stan  
}

transformed data {
#include /transformed_data/xh_marker.stan  
}


parameters {
  // ARMA parameters
#include /parameters/arma.stan
  // predictor for H
  vector[nt] beta;
  // DF constant nu for student t
  real< lower = 2 > nu;
  
  
   // GARCH h parameters on variance metric
  vector<lower=0>[nt] c_h;
  vector<lower=0 >[nt] a_h[Q];
  vector<lower=0, upper = 1 >[nt] b_h[P]; // TODO actually: 1 - a_h, across all Q and P...

  // GARCH q parameters
  real<lower=0, upper = 1 > a_q; //
  real<lower=0, upper = (1 - a_q) > b_q; //
  corr_matrix[nt] S;  // DCC keeps this constant

  // inits
  cov_matrix[nt] H[T];
  corr_matrix[nt] R[T];
  vector[nt] rr[T-1];
  vector[nt] mu[T];
  vector[nt] D[T];
  cov_matrix[nt] Qr[T];
  vector[nt] Qr_sdi[T];
  vector[nt] u[T];
}

generated quantities {
  // Define matrix for rts prediction
  vector[nt] rts_p[ahead + max(Q,P)];
  cov_matrix[nt] H_p[ahead + max(Q,P)];
  corr_matrix[nt] R_p[ahead + max(Q,P)]; // 
  vector[nt] rr_p[ahead + max(Q,P)];
  vector[nt] mu_p[ahead + max(Q,P)];
  vector[nt] D_p[ahead + max(Q,P)];
  cov_matrix[nt] Qr_p[ahead + max(Q,P)];
  vector[nt] u_p[ahead + max(Q,P)];
  vector[nt] Qr_sdi_p[ahead + max(Q,P)];

  // Placeholders
  real<lower = 0> vd_p[nt];
  real<lower = 0> ma_d_p[nt];
  real<lower = 0> ar_d_p[nt];
  

  // Populate with non-NA values to avoid Error in stan
  rts_p[1:(ahead + max(Q,P)), ] = rts[ 1:(ahead + max(Q,P)), ];
  H_p[  1:(ahead + max(Q,P)), ] = H[  1:(ahead + max(Q,P)), ];
  mu_p[ 1:(ahead + max(Q,P)), ] = mu[ 1:(ahead + max(Q,P)), ];
  rr_p[ 1:(ahead + max(Q,P)), ] = rr[ 1:(ahead + max(Q,P)), ];
  D_p[  1:(ahead + max(Q,P)), ] = D[  1:(ahead + max(Q,P)), ];
  u_p[  1:(ahead + max(Q,P)), ] = u[  1:(ahead + max(Q,P)), ];
  Qr_p[ 1:(ahead + max(Q,P)), ] = Qr[ 1:(ahead + max(Q,P)), ];
  Qr_sdi_p[ 1:(ahead + max(Q,P)), ] =Qr_sdi[ 1:(ahead + max(Q,P)), ];
  
  R_p[ 1:(ahead + max(Q,P)), ] = R[ 1:(ahead + max(Q,P)), ];

  // Obtain needed elements from mu and fill into mu_p
  rts_p[1:max(Q, P), ] = rts[ (T-(max(Q,P)-1) ):T, ];
  H_p[  1:max(Q, P), ] =  H[ (T-(max(Q,P)-1) ):T, ];
  mu_p[ 1:max(Q, P), ] = mu[ (T-(max(Q,P)-1) ):T, ];
  // rr is of length T-1
  rr_p[ 1:max(Q, P), ] = rr[ (T-1-(max(Q,P)-1) ):(T-1), ];
  D_p[  1:max(Q, P), ] =  D[ (T - (max(Q,P)-1) ):T, ];
  u_p[  1:max(Q, P), ] =  u[ (T - (max(Q,P)-1) ):T, ];
  Qr_p[ 1:max(Q, P), ] = Qr[ (T - (max(Q,P)-1) ):T, ];
  R_p[  1:max(Q, P), ] =  R[ (T - (max(Q,P)-1) ):T, ];
  
  // Forecast
  for (t in (max(Q, P) + 1 ):( max(Q, P) + ahead ) ){
    
    if( meanstructure == 0 ){
      mu_p[t, ] = phi0;
    } else if( meanstructure == 1 ){
      mu_p[t, ] = phi0 + phi * rts_p[t-1, ] + theta * (rts_p[t-1, ] - mu_p[t-1,]) ;
    }

    for(d in 1:nt){
      vd_p[d]   = 0.0;
      ma_d_p[d] = 0.0;
      ar_d_p[d] = 0.0;
      // GARCH MA component
      for (q in 1:min( t-1, Q) ) {
	rr_p[t-q, d] = square( rts_p[t-q, d] - mu_p[t-q, d] );
	ma_d_p[d] = ma_d_p[d] + a_h[q, d] * rr_p[t-q, d] ;
      }
      // GARCH AR component
      for (p in 1:min( t-1, P) ) {
      	ar_d_p[d] = ar_d_p[d] + b_h[p, d] * D_p[t-p, d];
      }

      // Predictor on diag (given in xH)
      if ( xH_marker >= 1) {
	vd_p[d] = c_h[d] + beta[d] * xH[t, d] + ma_d_p[d] + ar_d_p[d];
      } else if ( xH_marker == 0) {
      	vd_p[d] = c_h[d]  + ma_d_p[d] + ar_d_p[d];
      }

      D_p[t, d] = sqrt( vd_p[d] );
    }
    u_p[t,] = diag_matrix(D_p[t,]) \ (rts_p[t,]- mu_p[t,]);
    Qr_p[t,] = (1 - a_q - b_q) * S + a_q * (u_p[t-1,] * u_p[t-1,]') + b_q * Qr_p[t-1,];
    Qr_sdi_p[t,] = 1 ./ sqrt(diagonal(Qr_p[t,]));
    R_p[t,] = quad_form_diag(Qr_p[t,], Qr_sdi_p[t,]);
    H_p[t,] = quad_form_diag(R_p[t,],     D_p[t,]);
       
  
    if ( distribution == 0 ) {
      rts_p[t,] = multi_normal_rng( mu_p[t,], H_p[t,]);
    } else if ( distribution == 1 ) {
      rts_p[t,] = multi_student_t_rng( nu, mu_p[t,], H_p[t,]);
    }
  }
}
