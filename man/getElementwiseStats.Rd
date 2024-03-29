% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/MAUDE.R
\name{getElementwiseStats}
\alias{getElementwiseStats}
\title{Find active elements by annotation}
\usage{
getElementwiseStats(experiments, normNBSummaries, elementIDs, tails = "both",
  nonTargeting = "NT", ...)
}
\arguments{
\item{experiments}{a data.frame containing the headers that demarcate the screen ID, which are all also present in normNBSummaries}

\item{normNBSummaries}{data.frame of guide-level statistics as generated by findGuideHits()}

\item{elementIDs}{the names of one or more columns within guideLevelStats that contain the element annotations.}

\item{tails}{whether to test for increased expression ("upper"), decreased ("lower"), or both ("both"); (defaults to "both")}

\item{nonTargeting}{the name in normNBSummaries containing a logical representing whether or not the guide is non-Targeting (i.e. a negative control guide).  Defaults to "NT"}

\item{...}{other parameters for getZScalesWithNTGuides}
}
\value{
a data.frame containing the statistics for all elements
}
\description{
Tests guides for activity by considering a sliding window across the tested region and including all guides within the window for the test.
}
\examples{
allGuideLevelStats = findGuideHitsAllScreens(myScreens, allDataCounts, allBinStats)
elementLevelStats = getElementwiseStats(unique(allGuideLevelStats["screen"]),allGuideLevelStats, elementIDs="element",tails="upper")
}
