int<lower=1> T; // lengh of time series
int<lower=1> nt;    // number of time series
int<lower=1> Q; // MA component in MGARCH(P,Q), matrix A
int<lower=1> P; // AR component in MGARCH(P,Q), matrix B
vector[nt] rts[T];  // multivariate time-series
vector[nt] xH[T];  // time-varying predictor for conditional H
int<lower=0, upper=1> distribution; // 0 = Normal; 1 = student_t
int<lower=0, upper=1> meanstructure; // Select model for location
