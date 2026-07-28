# frozen_string_literal: true

# Loads the native plugin loader once at boot so `Plugins` is defined process
# wide before any request. The views and renderer also require it relatively,
# but that runs only when Zeitwerk first autoloads the referencing file — so
# whichever native-touching endpoint is hit first would otherwise race on an
# undefined `Plugins` constant. Requiring here removes the order dependency.
require_relative "../../vendor/plugins/support/loader"
