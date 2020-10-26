# ---+ Extensions
# ---++ ICalPlugin
# This is the configuration used by the <b>ICalPlugin</b>.

# **STRING LABEL="Cache Expiration"**
# Expiration time when fetching and caching exchange rates from the provider.
$Foswiki::cfg{ICalPlugin}{CacheExpire} = '1 d';

# **NUMBER**
# Network timeout in seconds talking to the rates provider API.
$Foswiki::cfg{ICalPlugin}{Timeout} = 5;

1;
