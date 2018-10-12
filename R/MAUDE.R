
#library(codetools)

#' Combines Z-scores using Stouffer's method
#'
#' This function takes a vector of Z-scores and combines them into a single Z-score using Stouffer's method.
#' @param x a vector of Z-scores to be combined
#' @return Returns a single Z-score.
#' @export
#' @examples
#' combineZStouffer(rnorm(10))
combineZStouffer = function(x){sum(x, na.rm=T)/sqrt(sum(!is.na(x)))}

#' Calculate the log likelihood of observed read counts
#'
#' Uses a normal distribution (N(mu,sigma)) to estimate how many reads are expected per bin under nullModel, and calculates the log likelihood under a negative binomial model.
#' @param x a vector of guide counts per bin
#' @param mu the mean for the normal expression distribution
#' @param k the vector of total counts per bin
#' @param sigma for the normal expression distribution (defaults to 1)
#' @param nullModel the bin bounds for the null model (for no change in expression)
#' @param libFract the fraction of the unsorted library this guide comprises (e.g. from unsorted cells, or sequencing the vector)
#' @return the log likelihood
#' @export
#' @examples
#' #usually not used directly
getNBGaussianLikelihood = function(x, mu, k, sigma=1, nullModel, libFract){
  #mu = mean of distribution
  #k = vector of total counts per bin
  #sigma = sigma for normal distribution
  #nullModel = bin bounds for null model
  #calculate the probabilities of being within each bin
  binFractions = pnorm(nullModel$binEndZ-mu) - pnorm(nullModel$binStartZ-mu)
  #message(sprintf("binFractions = %s",paste(as.character((binFractions)),collapse=", ")))
  binFractions = binFractions*libFract/(nullModel$binEndQ - nullModel$binStartQ)
  #message(sprintf("scaled binFractions = %s",paste(as.character((binFractions)),collapse=", ")))
  likelihood =0;
  #message(sprintf("observed fractions = %s",paste(as.character(((x/k))),collapse=", ")))
  for (i in 1:6){
    #dnbinom(x = number of reads for this guide, size = number of reads total, prob= probability of getting a read at each drawing)
    likelihood = likelihood  + dnbinom(x=x[i], size=k[i], prob =1- binFractions[i], log=T)
  }
  return(likelihood)
}
#checkUsage(getNBGaussianLikelihood)

#' Create a bin model for a single experiment
#'
#' Provided with the fractions captured by each bin, creates a bin model for use with MAUDE analysis, assuming 3 contiguous bins on the tails of the distribution.
#' @param curBinBounds  a data.frame containing three columns: Bin {A,B,C,D,E,F}, and fraction (the fractions of the total captured by each bin)
#' @param tailP the fraction of the tails of the distribution not captured in any bin (defaults to 0.001)
#' @return returns a data.frame with additional columns including the bin starts and ends in Z-score space, and in quantile space.
#' @export
#' @examples
#' binBounds = makeBinModel(data.frame(Bin=c("A","B","C","D","E","F"), fraction=rep(0.1,6))) #generally, this is retrieved from the FACS data
#' p = ggplot() + geom_vline(xintercept = sort(unique(c(binBounds$binStartZ,binBounds$binEndZ))),colour="gray") + theme_classic()+ xlab("Target expression") + geom_segment(data=binBounds, aes(x=binStartZ, xend=binEndZ, colour=Bin, y=0, yend=0), size=5, inherit.aes = F); print(p)
makeBinModel = function(curBinBounds,tailP=0.001){
  curBinBounds$binStartQ[curBinBounds$Bin=="A"]=tailP #A
  curBinBounds$binEndQ[curBinBounds$Bin=="A"] = curBinBounds$binStartQ[curBinBounds$Bin=="A"] + curBinBounds$fraction[curBinBounds$Bin=="A"];
  curBinBounds$binStartQ[curBinBounds$Bin=="B"] = curBinBounds$binEndQ[curBinBounds$Bin=="A"]; #B
  curBinBounds$binEndQ[curBinBounds$Bin=="B"] = curBinBounds$binStartQ[curBinBounds$Bin=="B"] + curBinBounds$fraction[curBinBounds$Bin=="B"];
  curBinBounds$binStartQ[curBinBounds$Bin=="C"] = curBinBounds$binEndQ[curBinBounds$Bin=="B"]; #C
  curBinBounds$binEndQ[curBinBounds$Bin=="C"] = curBinBounds$binStartQ[curBinBounds$Bin=="C"] + curBinBounds$fraction[curBinBounds$Bin=="C"];
  curBinBounds$binEndQ[curBinBounds$Bin=="F"]=1-tailP # F
  curBinBounds$binStartQ[curBinBounds$Bin=="F"] = curBinBounds$binEndQ[curBinBounds$Bin=="F"] - curBinBounds$fraction[curBinBounds$Bin=="F"];
  curBinBounds$binEndQ[curBinBounds$Bin=="E"] = curBinBounds$binStartQ[curBinBounds$Bin=="F"]; #E
  curBinBounds$binStartQ[curBinBounds$Bin=="E"] = curBinBounds$binEndQ[curBinBounds$Bin=="E"] - curBinBounds$fraction[curBinBounds$Bin=="E"];
  curBinBounds$binEndQ[curBinBounds$Bin=="D"] = curBinBounds$binStartQ[curBinBounds$Bin=="E"]; #D
  curBinBounds$binStartQ[curBinBounds$Bin=="D"] = curBinBounds$binEndQ[curBinBounds$Bin=="D"] - curBinBounds$fraction[curBinBounds$Bin=="D"];
  curBinBounds$binStartZ = qnorm(curBinBounds$binStartQ)
  curBinBounds$binEndZ = qnorm(curBinBounds$binEndQ)
  return(curBinBounds)
}
#checkUsage(makeBinModel)

#' Calculate guide-level statistics for a single screen
#'
#' Given a table of counts per guide/bin and a bin model for an experiment, calculate the optimal mean expression for each guide
#' @param countTable a table containing one column for each bin (A-F) and another column for non-targeting guide (logical-"NT"), and unsorted abundance (NS)
#' @param curBinBounds a bin model as created by makeBinModel
#' @param pseudocount the count to be added to each bin count, per 1e6 reads/bin total (default=10 pseudo reads per 1e6 reads total)
#' @param meanFunction how to calculate the mean of the non-targeting guides for centering Z-scores.  Defaults to 'mean'
#' @return a data.frame containing the guide-level statistics, including the Z score 'Z', log likelihood ratio 'llRatio', and estimated mean expression 'mean'.
#' @export
#' @examples
#' guideLevelStats = findGuideHits(binReadMat, binBounds)
findGuideHits = function(countTable, curBinBounds, pseudocount=10, meanFunction = mean){
  allBins = c("A","B","C","D","E","F")
  if (pseudocount>0){
    for(b in allBins){
      countTable[b]=countTable[b]+max(1,round(pseudocount*(sum(countTable[b])/1E6)));#add a pseudocount in proportion to depth
    }
    #countTable[allBins]=countTable[allBins]+pseudocount;#add a pseudocount
    countTable["NS"]=countTable["NS"]+pseudocount;
  }
  curNormNBSummaries = countTable
  countTable$libFraction = countTable$NS/sum(countTable$NS,na.rm=T)
  
  curNormNBSummaries$libFraction = curNormNBSummaries$NS/sum(curNormNBSummaries$NS,na.rm=T)
  binCounts = apply(curNormNBSummaries[allBins],2,function(x){sum(x, na.rm = T)})
  
  #for each guide, find the optimal mu given the count data and bin percentages
  for (i in 1:nrow(curNormNBSummaries)){
    #interval: The probability of observing a guide outside of this interval in one of the non-terminal bins is very unlikely, and so estimating a true mean for these is too difficult anyway. Besides, we get some local optima at the extremes for sparsely sampled data.
    temp = optimize(f=function(mu){getNBGaussianLikelihood(x=as.numeric(curNormNBSummaries[allBins][i,]), mu=mu, k=binCounts, nullModel=curBinBounds, libFract = curNormNBSummaries$libFraction[i])}, interval=c(-4,4), maximum = T)
    #TODO: This function can get stuck in local minima. Pseudocounts help prevent this, but it can still happen, resulting in a negative logliklihood ratio (i.e. Null is more likely than optimized alternate).  Usually this happens close to an effect size of 0.  I should still explore other optimization functions (e.g. optim)
    curNormNBSummaries$mean[i]=temp$maximum
    curNormNBSummaries$ll[i]=temp$objective
  }
  #recalculate LL ratio and calculate a Z score for the mean WRT the observed mean expression of the non-targeting (NT) guides
  muNT = meanFunction(curNormNBSummaries$mean[curNormNBSummaries$NT]) # mean of the non-targeting guides mean expressions
  for (i in 1:nrow(curNormNBSummaries)){
    curNormNBSummaries$llRatio[i]=curNormNBSummaries$ll[i] -getNBGaussianLikelihood(x=as.numeric(curNormNBSummaries[allBins][i,]), mu=muNT, k=binCounts, nullModel=curBinBounds, libFract = curNormNBSummaries$libFraction[i])
    curNormNBSummaries$Z[i]=curNormNBSummaries$mean[i]-muNT
  }
  return(curNormNBSummaries)
}
#checkUsage(findGuideHits)


#' Calculate Z-score scaling factors using non-targeting guides
#'
#' Calculates scaling factors to calibrate  element-wise Z-scores by repeatedly calculating a set of "null" Z-scores by repeatedly sampling the given numbers of non-targeting guides per element.
#' @param ntData data.frame containing the data for the non-targeting guides
#' @param uGuidesPerElement a unique vector of guide counts per element
#' @param mergeBy usually contains a data.frame containing the headers that demarcate the screen ID
#' @param ntSampleFold how many times to sample each non-targeting guide to make the Z score scale (defaults to 10)
#' @return a data.frame containing a Z-score scaling factor, one for every number of guides and unique entry in mergeBy
#' @export
#' @examples
#' #not generally used directly
getZScalesWithNTGuides = function(ntData, uGuidesPerElement, mergeBy, ntSampleFold=10){
  message(sprintf("Building background with %i non-targeting guides", nrow(ntData)))
  ntData = ntData[sample(1:nrow(ntData), nrow(ntData)*ntSampleFold, replace=T),]
  zScales = data.frame();
  for(i in uGuidesPerElement){
    ntData = ntData[order(runif(nrow(ntData))),]
    for(sortBy in mergeBy){ ntData = ntData[order(ntData[sortBy]),]} #sort by screen, then by random
    ntData$groupID = floor((0:(nrow(ntData)-1))/i)
    message(sprintf("Unique groups for %i guides per locus: %i", i, length(unique(ntData$groupID))))
    #message(str(ntData))
    ntStats = as.data.frame(cast(ntData, as.formula(sprintf("%s + groupID ~ .", paste(mergeBy, collapse = " + "))), value="Z", fun.aggregate = function(x){return(list(numGuides = length(x), stoufferZ=combineZStouffer(x)))}))
    #message(str(ntStats))
    ntStats = ntStats[ntStats$numGuides==i,]
    #message(str(ntStats))
    ntStats = as.data.frame(cast(ntStats, as.formula(sprintf("%s ~ .", paste(mergeBy, collapse = " + "))), value="stoufferZ",fun.aggregate = function(x){sd(x,na.rm=T)}))
    names(ntStats)[ncol(ntStats)]="Zscale"
    ntStats$numGuides=i;
    #message(str(ntStats))
    zScales = rbind(zScales, ntStats)
  }
  return(zScales)
}
#checkUsage(getZScalesWithNTGuides)

#' Find active elements by sliding window
#'
#' Tests guides for activity by considering a sliding window across the tested region and including all guides within the window for the test.
#' @param experiments a data.frame containing the headers that demarcate the screen ID, which are all also present in normNBSummaries
#' @param normNBSummaries data.frame of guide-level statistics as generated by findGuideHits()
#' @param tails whether to test for increased expression ("upper"), decreased ("lower"), or both ("both"); (defaults to "both")
#' @param location the name of the column in normNBSummaries containing the chromosomal location (defaults to "pos")
#' @param chr the name of the column in normNBSummaries containing the chromosome name (defaults to "chr")
#' @param window the window width in base pairs (defaults to 500)
#' @param minGuides the minimum number of guides in a window required for a test (defaults to 5)
#' @param ... other parameters for getZScalesWithNTGuides
#' @return a data.frame containing the statistics for all windows tested for activity
#' @export
#' @examples
#' allGuideLevelStats = findGuideHitsAllScreens(myScreens, allDataCounts, allBinStats)
#' elementLevelStatsTiling = getTilingElementwiseStats(myScreens, allGuideLevelStats, tails = "upper")
getTilingElementwiseStats = function(experiments, normNBSummaries, tails="both", location="pos", chr="chr", window=500, minGuides=5, ...){
  if(!location %in% names(normNBSummaries)){
    stop(sprintf("Column '%s' is missing from normNBSummaries", location))
  }
  if(!"Z" %in% names(normNBSummaries)){
    stop(sprintf("Column 'Z' is missing from normNBSummaries"))
  }
  if(!chr %in% names(normNBSummaries)){
    stop(sprintf("Column '%s' is missing from normNBSummaries", chr))
  }
  experiments = unique(experiments);
  mergeBy = names(experiments);
  ntData = normNBSummaries[normNBSummaries$NT,]
  normNBSummaries = normNBSummaries[!normNBSummaries$NT,]
  elementwiseStats = data.frame();
  for (i in 1:nrow(experiments)){
    #message(i)
    for (curChr in unique(normNBSummaries[[chr]])){
      #message(curChr)
      curData = merge(experiments[i,],normNBSummaries[normNBSummaries[[chr]]==curChr,])
      curData = curData[order(curData[location]),]
      lagging=1
      leading=1
      while (leading <=nrow(curData)){
        #message(names(curData))
        #message(window)
        #message(head(curData[[location]]))
        while (curData[[location]][lagging] + window < curData[[location]][leading]){
          lagging = lagging +1;
        }
        while (leading+1 <=nrow(curData) && curData[[location]][lagging] + window >= curData[[location]][leading+1]){
          leading = leading +1;
        }
        #message(sprintf("%i:%i %s:%i-%i",lagging,leading, curChr, curData[[location]][lagging], curData[[location]][leading]))
        if (leading-lagging +1 >= minGuides){
          elementwiseStats = rbind(elementwiseStats, data.frame(experiments[i,], chr = curChr, start = curData[[location]][lagging], end = curData[[location]][leading], numGuides = leading-lagging+1, stoufferZ=combineZStouffer(curData$Z[lagging:leading]), meanZ=mean(curData$Z[lagging:leading])))
        }
        leading = leading + 1;
      }
    }
  }
  elementwiseStats = elementwiseStats[order(elementwiseStats$stoufferZ),]
  #head(elementwiseStats)
  #calibrate Z scores
  uGuidesPerElement = sort(unique(elementwiseStats$numGuides))
  zScales = data.frame();
  #build background
  zScales = getZScalesWithNTGuides(ntData,uGuidesPerElement, mergeBy, ...)
  elementwiseStats = merge(elementwiseStats, zScales, by=c(mergeBy,"numGuides"))
  elementwiseStats$rescaledZ = elementwiseStats$stoufferZ/elementwiseStats$Zscale;
  if (tails=="both" || tails =="lower"){
    elementwiseStats$p.value = pnorm(elementwiseStats$rescaledZ)
  }
  if (tails=="both"){
    elementwiseStats$p.value[elementwiseStats$rescaledZ>0] = pnorm(-elementwiseStats$rescaledZ[elementwiseStats$rescaledZ>0])
  }
  if (tails=="upper"){
    elementwiseStats$p.value = pnorm(-elementwiseStats$rescaledZ)
  }
  elementwiseStats$FDR = p.adjust(elementwiseStats$p.value, method = "BH", n = nrow(elementwiseStats) + ((tails=="both") * nrow(elementwiseStats)))
  elementwiseStats$Zscale=NULL
  return(elementwiseStats);
}
#checkUsage(getTilingElementwiseStats)

#' Find active elements by annotation
#'
#' Tests guides for activity by considering a sliding window across the tested region and including all guides within the window for the test.
#' @param experiments a data.frame containing the headers that demarcate the screen ID, which are all also present in normNBSummaries
#' @param normNBSummaries data.frame of guide-level statistics as generated by findGuideHits()
#' @param elementIDs the names of one or more columns within guideLevelStats that contain the element annotations.
#' @param tails whether to test for increased expression ("upper"), decreased ("lower"), or both ("both"); (defaults to "both")
#' @param ... other parameters for getZScalesWithNTGuides
#' @return a data.frame containing the statistics for all elements
#' @export
#' @examples
#' allGuideLevelStats = findGuideHitsAllScreens(myScreens, allDataCounts, allBinStats)
#' elementLevelStats = getElementwiseStats(unique(allGuideLevelStats["screen"]),allGuideLevelStats, elementIDs="element",tails="upper")
getElementwiseStats = function(experiments, normNBSummaries, elementIDs, tails="both",...){
  experiments = unique(experiments);
  mergeBy = names(experiments);
  ntData = normNBSummaries[normNBSummaries$NT,]
  normNBSummaries = normNBSummaries[!normNBSummaries$NT,]
  elementwiseStats = cast(normNBSummaries[!apply(is.na(normNBSummaries[elementIDs]), 1, any),], as.formula(sprintf("%s ~ .", paste(c(elementIDs, mergeBy), collapse = " + "))), value="Z", fun.aggregate = function(x){return(list(numGuides = length(x), stoufferZ=combineZStouffer(x), meanZ=mean(x)))})
  elementwiseStats = elementwiseStats[order(elementwiseStats$stoufferZ),]
  #head(elementwiseStats)
  #calibrate Z scores
  uGuidesPerElement = sort(unique(elementwiseStats$numGuides))
  #build background
  zScales = getZScalesWithNTGuides(ntData,uGuidesPerElement, mergeBy, ...)
  elementwiseStats = merge(elementwiseStats, zScales, by=c(mergeBy,"numGuides"))
  elementwiseStats$rescaledZ = elementwiseStats$stoufferZ/elementwiseStats$Zscale;
  if (tails=="both" || tails =="lower"){
    elementwiseStats$p.value = pnorm(elementwiseStats$rescaledZ)
  }
  if (tails=="both"){
    elementwiseStats$p.value[elementwiseStats$rescaledZ>0] = pnorm(-elementwiseStats$rescaledZ[elementwiseStats$rescaledZ>0])
  }
  if (tails=="upper"){
    elementwiseStats$p.value = pnorm(-elementwiseStats$rescaledZ)
  }
  elementwiseStats$FDR = p.adjust(elementwiseStats$p.value, method = "BH", n = nrow(elementwiseStats) + ((tails=="both") * nrow(elementwiseStats)))
  elementwiseStats$Zscale=NULL
  return(elementwiseStats);
}
#checkUsage(getElementwiseStats)

#' Calculate guide-level stats for multiple experiments
#'
#' Uses findGuideHits to find guide-level stats for each unique entry in 'experiments'.
#' @param experiments a data.frame containing the headers that demarcate the screen ID, which are all also present in countDataFrame and binStats
#' @param countDataFrame a table containing one column for each bin (A-F) and another column for non-targeting guide (logical-"NT"), and unsorted abundance (NS), as well as columns corresponding to those in  'experiments' 
#' @param binStats a bin model as created by makeBinModel, as well as columns corresponding to those in  'experiments'
#' @param ... other parameters for findGuideHits
#' @return guide-level stats for all experiments
#' @export
#' @examples
#'  allGuideLevelStats = findGuideHitsAllScreens(myScreens, allDataCounts, allBinStats)
findGuideHitsAllScreens = function(experiments, countDataFrame, binStats, ...){
  if (!"Bin" %in% names(binStats)){
    if (!"bin" %in% names(binStats)){
      warning("'Bin' column not found in binStats; using 'bin' instead")
      binStats$Bin = binStats$bin;
    }else{
      stop("No 'Bin' column in binStats!")
    }
  }
  if (!"fraction" %in% names(binStats)){
    stop("No 'frequency' column in binStats!")
  }
  if (!all(c("A","B","C","D","E","F","NS") %in% names(countDataFrame))){
    stop("Not all bins (A-F, NS) present in countDataFrame!")
  }
  experiments = unique(experiments);
  mergeBy = names(experiments);
  if (!all(mergeBy %in% names(countDataFrame))){
    message(names(experiments))
    message(names(countDataFrame))
    stop("Columns from 'experiments' missing from 'countDataFrame'");
  }
  if (!all(mergeBy %in% names(binStats))){
    stop("Columns from 'experiments' missing from 'binStats'");
  }
  experiments[ncol(experiments)+1]=1:nrow(experiments);
  idCol = names(experiments)[ncol(experiments)];
  countDataFrame = merge(countDataFrame, experiments, by=mergeBy);
  binStats = merge(binStats, experiments, by=mergeBy);
  
  allSummaries = data.frame()
  for(j in 1:nrow(experiments)){
    normNBSummaries = findGuideHits(
      countDataFrame[countDataFrame[[idCol]]==experiments[[idCol]][j],], 
      makeBinModel(binStats[binStats[[idCol]]==experiments[[idCol]][j] , c("Bin","fraction")]), ...)
    allSummaries = rbind(allSummaries,normNBSummaries)
  }
  allSummaries[[idCol]]=NULL;
  return(allSummaries);
}
#checkUsage(findGuideHitsAllScreens)
