#' retrieve vegetation structure data  from NEON
#'
#'
#' @return
#' @export
#' @examples
#' @importFrom magrittr "%>%"
#' @import plsRglm
pls_glm <- function(ll = NULL, trait = NULL, nrmlz=F){

    wrangle = function(x){
      ifelse(is.character(x), x[1], mean(x, na.rm=T))
    }
    #get traits data
    cr.Traits <- readr::read_csv(paste("./indir/Traits/field_data.csv",sep=""))
    cr.Traits = cr.Traits %>% group_by(individualID) %>% summarize_all(wrangle)
    cr.Traits = cr.Traits[complete.cases(cr.Traits),]
    train_ids = readr::read_csv("./indir/Misc/train_ids.csv")
    calib_ids = readr::read_csv("./indir/Misc/calibration_ids.csv")
    test_ids = readr::read_csv("./indir/Misc/oob_ids.csv")

    #get random flip spectra data
    aug.spectra <- readr::read_csv(paste('./indir/Permutations/onePix1Crown_', ll, '.csv', sep = ''))

    aug.spectra <- inner_join(cr.Traits, aug.spectra, by = "individualID")
    aug.spectra = aug.spectra %>% filter(!individualID %in% test_ids)
    tmp_features<- aug.spectra[grepl("band", names(aug.spectra))]
    tmp_variables <- aug.spectra[names(aug.spectra) %in% trait]
    tmp_variables <- (round(tmp_variables,3))
    bnd_site <- aug.spectra[["SITE"]] %>% factor %>% fastDummies::dummy_cols()
    colnames(bnd_site) <- stringr::str_replace(colnames(bnd_site), ".data_", "band_")
    aug.spectra <- data.frame(aug.spectra["individualID"], aug.spectra["taxonID"], bnd_site[-1], tmp_features, tmp_variables)
    aug.spectra = aug.spectra[complete.cases(aug.spectra),]
    # Subset data into cal/val by site
    train.data = aug.spectra %>% filter(individualID %in% train_ids$individualID)
    test.data = aug.spectra %>% filter(individualID %in% calib_ids$individualID)
    test.data = aug.spectra %>% filter(individualID %in% test_ids$individualID)

    #predictors matrix
    train.data= train.data %>% dplyr::select(-one_of("band_site"))
    test.data= test.data %>% dplyr::select(-one_of("band_site"))

    X <- as.matrix(train.data[grepl("band", names(train.data))])
    #responses matrix
    Y <- as.vector(train.data[,names(train.data) %in% trait])
    Y
    #K=nrow(Y)
    #get sites and set up sites fixed effects
    nsites <- nrow(unique(bnd_site))
    # if(nrmlz==T){
    #   X.n <- t(diff(t((X[,-c(1:nsites)])),differences=1, lag=3))
    #   X <- cbind(X[,c(1:nsites)], X.n)
    # }
    if(nsites==1){
      X = X[,-1]
    }
    set.seed(ll)
    #perform a cross-valiadation on train-validation set
    train.PLS<- plsRglm::cv.plsRglm(dataY=log(Y),dataX=X, scaleY = T, verbose=F,
                                    nt=15,NK=1, K=10,
                                    modele="pls-glm-family",family=gaussian())
    out <- list()
    #define number of components to chose by calculating PRESS statistics
    press <- unlist(plsRglm::kfolds2Press(train.PLS))
    out["ncomp"] = max(which(press == min(press)), 4)

    # retrain on chosen number of components
    set.seed(ll)
    mod <- plsRglm::plsRglm(dataY=log(Y),dataX=X,as.integer(out["ncomp"]), scaleY = T,
                            modele="pls-glm-family",family=gaussian())
    X.tst <- as.matrix(test.data[grepl("band", names(test.data))])
    # if(nrmlz==T){
    #   X.ntst <-t(diff(t((X.tst[,-c(1:nsites)])),differences=1, lag=3))
    #   X.tst <- cbind(X.tst[,c(1:nsites)], X.ntst)
    # }
    if(nsites==1){
      X.tst = X.tst[,-1]
    }
    #mod = LMA$mod
    #out["ncomp"] = LMA$ncomp
    #store validation metrics
    Y.test <- as.vector(test.data[,names(test.data) %in% trait])
    #Y.test = round(Y.test, 2)
    out[["pred"]] <- exp(pls_glm_predict(mod, newdata=X.tst,
                             type="response", comps=as.integer(out["ncomp"])))
    #out[["pred"]] = round(out[["pred"]], 2)
    out[["pR2"]] <- 1 - sum((out[["pred"]][,1] - (Y.test))^2) /
      sum((Y.test - mean(Y.test))^2)
    #plot(out$pred[,1], Y.test)
    out[["mod"]] <- mod
    out[["pR2"]]
    a = rmse(out$pred[,1], Y.test)
    lw = out$pred[,2] <Y.test
    up = out$pred[,3] > Y.test
    sum(lw*up)/length(Y.test)
    rmse_ = rmse(Y.test, out[["pred"]])
    rmse_
    rmse_ / abs(diff(range(Y.test)))
    saveRDS(out, paste("./outdir/PBMs/pls_glm_", trait, ll, ".rds", sep=""))
  return(out)
}

pls_glm_predict <- function(object,newdata,
                            comps=object$computed_nt, type=c("link", "response", "terms", "scores", "class", "probs"),
                            se.fit=FALSE, wt = NULL, dispersion = NULL,methodNA="adaptative",verbose=TRUE,...)
{
  nrnd <- nrow(newdata)
  newdataNA <- !is.na(newdata)
  newdata <- sweep(sweep(newdata, 2, attr(object$ExpliX, "scaled:center")),
                   2, attr(object$ExpliX, "scaled:scale"), "/")
  newdata <- as.matrix(newdata)
  #newdata[!newdataNA] <- 0
  newdata = lapply(1:nrnd, function(x)c(newdata[x,] %*% object$wwetoile[, 1:comps],
                                        rep(0, object$computed_nt - comps)))
  newdata = do.call(rbind, newdata)
  colnames(newdata) <- NULL
  newdata <- data.frame(tt = newdata)
  pred_int = HH::interval(object$FinalModel, newdata=newdata, type="response")
  pred_int = pred_int[,c(1,4,5)]
  colnames(pred_int) = c("fit","lwr","upr")
  return(pred_int)
}


