/// Whether tapping a bottom-nav tab should start a data fetch.
///
/// First visit / failed load: fetch. Already loaded or in-flight: do not.
bool shouldFetchOnTabSelect({
  required bool hasSuccessfullyLoaded,
  required bool isLoadInProgress,
}) {
  return !hasSuccessfullyLoaded && !isLoadInProgress;
}
