#!/bin/bash

# Shared utilities for Jenkins CI scripts

# Cleans and normalizes Cypress tags:
# 1. Removes the @bypass magic tag
# 2. Converts spaces to + (AND logic)
# 3. Collapses multiple + into one
# 4. Trims leading/trailing +
clean_tags() {
	local tags="$1"
	echo "${tags}" | sed -e 's/@bypass//g' -e 's/[[:space:]][[:space:]]*/+/g' -e 's/++*/+/g' -e 's/^+//' -e 's/+$//' -e 's/+-$//'
}
