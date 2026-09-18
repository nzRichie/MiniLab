#!/usr/bin/env bash
# The status action, for a sandbox named as this row's first argument.
#
# The action cannot ride in the menu's `script` string: the engine passes that
# string as one argv entry and everything after it comes from `args`,
# positionally. So each action is its own two-line wrapper.
exec "$( dirname "${BASH_SOURCE[0]}" )/sb-run.sh" status "$@"
