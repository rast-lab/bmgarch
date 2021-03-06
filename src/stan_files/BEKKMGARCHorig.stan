// BEKK-Parameterization
functions { 
#include /functions/cov2cor.stan
}
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
  //cov_matrix[ xH_marker >= 1 ? nt : 0 ] beta;
  row_vector[nt] beta0;
  vector[nt] beta1;
  
  // in case Cnst is predicted, separate into C_sd*C_R*C_sd
  corr_matrix[nt] C_R;

  
  // construct A, so that one element (a11) can be constrained to be non-negative
  real<lower = 0, upper = 1> Ap11[Q];
  row_vector[nt-2] Ap1k[Q];
  matrix[nt-1, nt-1] Ap_sub[Q];
  
  //
  real<lower = 0, upper = 1> Bp11[P];
  row_vector[nt-2] Bp1k[P];
  matrix[nt-1, nt-1] Bp_sub[P];

  //
  vector[nt] A_log[Q];
  vector[nt] B_log[P];


  // H1 init
  cov_matrix[nt] H1_init;
  real< lower = 2 > nu; // nu for student_t

}
transformed parameters {
  cholesky_factor_cov[nt] L_H[T];
  cov_matrix[nt] H[T];
  matrix[nt,nt] rr[T-1];
  vector[nt] mu[T];
  matrix[nt, nt] A[Q];
  matrix[nt, nt] B[P];
  vector[nt] Ca[Q]; // Upper (and lower) boundary for A 
  vector[nt] Av[Q];
  vector[nt] Cb[P]; // Upper (and lower) boundary for B
  vector[nt] Bv[P]; 
  matrix[nt, nt -1 ] Ap[Q];
  matrix[nt, nt -1 ] Bp[P];
  matrix[nt, nt] A_part = diag_matrix( rep_vector(0.0, nt));
  matrix[nt, nt] B_part = diag_matrix( rep_vector(0.0, nt));

  matrix[nt+1, nt] beta = append_row( beta0, diag_matrix(beta1) );
    row_vector[nt] C_sd;
//  cholesky_factor_cov[nt] Cnst; // Const is symmetric, A, B, are not
  cov_matrix[nt] Cnst; // Const is symmetric, A, B, are not  
  
  
  // Define matrix constraints
  for ( q in 1:Q )
    Ap[q] = append_row(append_col(Ap11[q], Ap1k[q]), Ap_sub[q]);
  for ( p in 1:P )
    Bp[p] = append_row(append_col(Bp11[p], Bp1k[p]), Bp_sub[p]);
  for ( i in 1:nt) {
    for ( q in 1:Q ){
      Ca[q,i] = sqrt( 1 - dot_self(Ap[q,i]) );
      Av[q,i] = -Ca[q,i] + 2*Ca[q,i] * inv_logit( A_log[q,i] );
    }
    for ( p in 1:P ){ 
      Cb[p,i] = sqrt( 1 - dot_self(Bp[p,i]) );
      Bv[p,i] = -Cb[p,i] + 2*Cb[p,i] * inv_logit( B_log[p,i] );
    }
  }
  
  for ( q in 1:Q ) 
    A[q] = append_col(Ap[q], Av[q]);

  for ( p in 1:P )
    B[p] = append_col(Bp[p], Bv[p]);

  // Initialize model parameters
  mu[1,] = phi0;
  H[1,] = H1_init;
  L_H[1,] = cholesky_decompose(H[1,]); // cf. p 69 in stan manual for how to index

  //
  for (t in 2:T){
    
    // Meanstructure model:
#include /model_components/mu.stan

    // reset A_part and B_part to zero for each iteration t
    A_part = diag_matrix( rep_vector(0.0, nt));
    B_part = diag_matrix( rep_vector(0.0, nt));
        
    for (q in 1:min( t-1, Q) ) {
      rr[t-q,] = ( rts[t-q,] - mu[t-q,] )*( rts[t-q,] - mu[t-q,] )';
      A_part = A_part + A[q]' * rr[t-q,] * A[q];
    }
    for (p in 1:min( t-1, P) ) {
      B_part = B_part + B[p]' * H[t-p,] * B[p];
    }
    if( xH_marker == 0 ) {
      C_sd = exp( beta0 ); 
      Cnst =  quad_form_diag(C_R, C_sd );
      H[t,] = Cnst + A_part +  B_part;
    } else if( xH_marker >= 1) {
      C_sd = exp( append_col( 1.0, xH[t]' ) * beta ); 
      Cnst =  quad_form_diag(C_R, C_sd );
      H[t,] = Cnst  + A_part +  B_part;
    }
    L_H[t,] = cholesky_decompose(H[t,]);
  }
}
model {
  // priors
  // Prior on nu for student_t
  if ( distribution == 1 )
    nu ~ normal( nt, 50 );
  // Prior for initial state
  H1_init ~ wishart(nt + 1.0, diag_matrix(rep_vector(1.0, nt)) );
  
  to_vector(theta) ~ normal(0, 1);
  to_vector(phi) ~ normal(0, 1);
  to_vector(phi0) ~ normal(0, 1);
  //  Cnst ~ wishart(nt + 1.0, diag_matrix(rep_vector(1.0, nt)) );
  to_vector(beta0) ~ normal(-2, 4);
  to_vector(beta1) ~ normal(0, 1);
  C_R ~ lkj_corr( 1 );
  
  for( k in 1:nt){ 
     for( q in 1:Q ) {
       target += uniform_lpdf(Av[q,k] | -Ca[q,k], Ca[q,k]) + log( 2*Ca[q,k] ) + log_inv_logit( A_log[q,k] ) + log1m_inv_logit( A_log[q,k] );
     }
     for ( p in 1:P ) {
       target += uniform_lpdf(Bv[p,k] | -Cb[p,k], Cb[p,k]) + log( 2*Cb[p,k] ) + log_inv_logit( B_log[p,k] ) + log1m_inv_logit( B_log[p,k] );
     }
  }
  // likelihood
  if ( distribution == 0 ) {
    for(t in 1:T){
      //      rts[t,] ~ multi_normal_cholesky(mu[t,], L_H[t,]);
      target += multi_normal_cholesky_lpdf( rts[t, ] | mu[t,], L_H[t,]);
    }
  } else if ( distribution == 1 ) {
    for(t in 1:T){
      // rts[t,] ~ multi_student_t(nu, mu[t,], L_H[t,]*L_H[t,]');
      target += multi_student_t_lpdf( rts[t, ] | nu, mu[t,], L_H[t,]*L_H[t,]');
    }
  }
}
//
generated quantities {
  matrix[nt,T] rts_out;
  real log_lik[T];
  corr_matrix[nt] corC;
  corr_matrix[nt] corH[T];
  row_vector[nt] C_var;

//Const = multiply_lower_tri_self_transpose(Cnst);
  corC = cov2cor(Cnst);
  C_var = exp( beta0 ) .* exp( beta0 );

  // retrodict
#include /generated/retrodict_H.stan

}
