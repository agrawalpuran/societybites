/**
 * Names produced by backend integration tests or local debug sessions.
 * Hidden from buyer marketplace feeds; used by cleanup-test-data.js.
 */
const AUTOMATED_TEST_LISTING_NAME =
  /^(Reach other-society \d|Eligibility other-society \d|Insights (Dhokla|Secret|Unsold) \d|History \d{10,}|PayPref \d{10,}|Other-society catalog \d|Bulk (active|paused|expired|inactive|preorder) \d|Other seller \d|Cancel \d{10,}|Lifecycle \d{10,}|Order reconciliation \d|Veg test \d|Non-veg test \d|Invalid type \d|Missing type \d|Egg veg \d|Legacy null foodType \d|Catalog (regular|preorder) \d|Nearby (regular|preorder) \d|Ready now( need-by)? \d|Preorder( ok)? \d|Bad mode \d|Missing prep \d|Bad prep \d|Cake \d{8,}|Second cake \d|Plain \d{8,}|Idli \d{8,}|Bad time \d|Bad limit \d|Pre \d{8,}|MTO( need-by)? \d|Messages \d{10,}|Regular (regression|dashboard) \d|Fulfilment other-society \d|P5 seed same \d|P4B other-society \d|Guest Regular Bowl|Guest Extended Thali|Guest Preorder Box|Hidden Society Meal|Pune Regular Meal|Dbg\d{8,})/;

function isAutomatedTestListingName(name) {
  if (name == null) return false;
  const text = String(name).trim();
  if (!text) return false;
  return AUTOMATED_TEST_LISTING_NAME.test(text);
}

function withoutAutomatedTestListings(listings) {
  if (!Array.isArray(listings) || listings.length === 0) return listings || [];
  return listings.filter((listing) => !isAutomatedTestListingName(listing.name));
}

module.exports = {
  AUTOMATED_TEST_LISTING_NAME,
  isAutomatedTestListingName,
  withoutAutomatedTestListings,
};
