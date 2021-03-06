#' Standardize input data to facilitate computation
#' 
#' @param data Time-series data
#'
#' @return bmgarch object 
#' @export
#' @keywords internal
standat = function(data, xH, P, Q, standardize_data, distribution, meanstructure){

    if(dim(data)[1] < dim(data)[2]) data = t(data)
    if ( is.null( colnames( data ) ) ) colnames( data ) = paste0('t', 1:ncol( data ) )

    ## Model for meanstructure
    if( meanstructure == 'constant') {
        meanstructure = 0
    } else {
        if ( meanstructure == 'arma') {
            meanstructure = 1
        }
    }
                                                       
    ## Tests on predictor
    ## Pass in a 0 matrix, so that stan does not complain
    if ( is.null( xH ) ) xH = matrix(0, nrow = nrow( data ), ncol = ncol( data) )
    ## Match dimension of predictor to TS. If only one vector is given, it's assumed that it is the same for all TS's
    if (  is.null( ncol( xH ) ) ) {
        warning("xH is assumed constant across TS's")
        xH = matrix( xH, nrow = nrow( data ), ncol = ncol( data)) ## Risky, better to throw an error
    } else { ## xH is not a vector  - check if it is of right dimension
        if( dim( xH )[2] != dim( data )[2] ) warning('xH is not of right dimension - adapt xH dimension to match number of TS')
        }

    if(standardize_data) {
    ## Standardize time-series
    stdx = scale(data)
    centered_data = attr(stdx, "scaled:center")
    scaled_data = attr(stdx, "scaled:scale")
    return_standat = list(T = nrow(stdx),
                          rts = stdx,
                          xH = xH,
                          nt = ncol(stdx),
                          centered_data = centered_data,
                          scaled_data = scaled_data,
                          distribution = distribution,
                          P = P,
                          Q = Q,
                          meanstructure = meanstructure)
    } else {
      ## Unstandardized
      return_standat = list(T = nrow(data),
                            rts = data,
                            xH = xH,
                            nt = ncol(data),
                            distribution = distribution,
                            P = P,
                            Q = Q,
                            meanstructure = meanstructure)
    }
    return(return_standat)
}

##' Draw samples from a specified multivariate GARCH model, given multivariate time-series.
##'
##' Three paramerizations are implemented. The constant conditinal correlation (CCC), the dynamic conditional correlation (DCC), and  BEKK.
##' @title Bayesian Multivariate GARCH
##' @param data A time-series or matrix object containing observations at the same interval.
##' @param xH 
##' @param parameterization A character string specifying the type of of parameterization, must be one of "CCC" (default), "DCC", or "BEKK".
##' @param P dimension of AR component in MGARCH(P,Q)
##' @param Q dimension of MA component in MGARCH(P,Q)
##' @param iterations A positive integer specifying the number of iterations for each chain (including warmup). The default is 1000
##' @param chains A positive integer specifying the number of Markov chains. The default is 4.
##' @param standardize_data 
##' @param distribution Distribution of innovation: "Student_t" (default) or "Normal" 
##' @param meanstructure Defines model for means. Either 'constant' (default) or 'arma'. Currently arma(1,1) only.
##' @param ... Additional arguments can be ‘chain_id’, ‘init_r’, ‘test_grad’, ‘append_samples’, ‘refresh’, ‘enable_random_init’. See the documentation in ‘stan’.
##' @return An object of S4 class ‘stanfit’ representing the fitted results.
##' @author Philippe Rast
##' @export
bmgarch = function(data,
                   xH = NULL,
                   parameterization = 'CCC',
                   P = 1,
                   Q = 1,
                   iterations = 1000,
                   chains = 4,
                   standardize_data = TRUE,
                   distribution = 'Student_t',
                   meanstructure = 'constant', ...) {
    num_dist = NA
    if ( distribution == 'Gaussian' ) num_dist = 0 else {
            if ( distribution == 'student_t' | distribution == 'Student_t') num_dist = 1 else warning( '\n\n Specify distribution: Gaussian or Student_t \n\n', immediate. = TRUE) }
    return_standat = standat(data, xH, P, Q,  standardize_data, distribution = num_dist, meanstructure )
    stan_data  = return_standat[ c('T', 'xH', 'rts', 'nt', 'distribution', 'P', 'Q', 'meanstructure')]

  if(parameterization == 'CCC') model_fit <- rstan::sampling(stanmodels$CCCMGARCH, data = stan_data,
                                                      verbose = TRUE,
                                                      iter = iterations,
                                                      control = list(adapt_delta = .99),
                                                      init_r = 1,
                                                      chains = chains) else {
  if( parameterization == 'DCC' ) model_fit <- rstan::sampling(stanmodels$DCCMGARCH, data = stan_data,
                                                      verbose = TRUE,
                                                      iter = iterations,
                                                      control = list(adapt_delta = .99),
                                                      init_r = 1,
                                                      chains = chains) else {
  if( parameterization == 'BEKK' ) model_fit <- rstan::sampling(stanmodels$BEKKMGARCH, 
                                                      data = stan_data,
                                                      verbose = TRUE,
                                                      iter = iterations,
                                                      control = list(adapt_delta = .99),
                                                      init_r = 1,
                                                      chains = chains) else {
  warning( 'Not a valid model specification. Select CCC, DCC, or BEKK.' )}
                                                                       }
                                                                       }
    ## Model fit is based on standardized values.
    mns = return_standat$centered_data
    sds = return_standat$scaled_data
    ## Values could be converted to original scale using something like this on the estimates
    ## orig_sd = stan_data$rts %*% diag(sds)
    ## orig_scale = orig_sd + array(rep(mns, each = aussi[[1]]$T), dim = c(aussi[[1]]$T, aussi[[1]]$nt) )
    return_fit <- list(model_fit = model_fit,
                       param = parameterization,
                       distribution = distribution,
                       num_dist = num_dist,
                       iter = iterations,
                       chains = chains,
                       elapsed_time = rstan::get_elapsed_time(model_fit),
                       date = date(),
                       nt = stan_data$nt,
                       TS_length = stan_data$T,
                       TS_names = colnames(stan_data$rts),
                       RTS_last = stan_data$rts[stan_data$T,],
                       RTS_full = stan_data$rts,
                       mgarchQ = stan_data$Q,
                       mgarchP = stan_data$P,
                       xH = stan_data$xH,
                       meanstructure = stan_data$meanstructure)
    class(return_fit) <- "bmgarch"
    return(return_fit)
}
