#!/bin/bash

set -eo pipefail

# Function to show usage information
usage() {
    echo "Usage: $0 --xcresult-path <path> --output-path <path>"
    echo
    echo "Options:"
    echo "  --xcresult-path    Path to the XCResult bundle"
    echo "  --output-path      Path where JUnit XML file will be saved"
    exit 1
}

# Parse command-line arguments
XCRESULT_PATH=""
OUTPUT_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --xcresult-path)
            XCRESULT_PATH="$2"
            shift 2
            ;;
        --output-path)
            OUTPUT_PATH="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate required arguments
if [ -z "$XCRESULT_PATH" ] || [ -z "$OUTPUT_PATH" ]; then
    usage
fi

# Check if xcresult file exists
if [ ! -d "$XCRESULT_PATH" ]; then
    echo "Error: XCResult bundle not found at $XCRESULT_PATH"
    exit 1
fi

# Create output directory if it doesn't exist
mkdir -p "$(dirname "$OUTPUT_PATH")"

# Step 1: Extract test results from xcresult
echo "Extracting test results from $XCRESULT_PATH..."
TEST_STRUCTURE=$(xcrun xcresulttool get test-results tests --path "$XCRESULT_PATH")
if [ $? -ne 0 ]; then
    echo "Error: Failed to extract test structure"
    exit 1
fi

# Step 2: Generate JUnit XML
echo "Generating JUnit XML..."

# Start XML document
cat > "$OUTPUT_PATH" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
EOF

# Process test structure using jq
# This requires jq to be installed: https://stedolan.github.io/jq/
if ! command -v jq &> /dev/null; then
    echo "Error: This script requires jq. Please install it and try again."
    exit 1
fi

# Extract timestamp
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S")

# Function to recursively process test cases from a node
process_test_cases() {
    local NODE="$1"
    local PARENT_CLASS_NAME="$2"
    local TEST_CASES_XML=""
    local TEST_CASES_COUNT=0
    local FAILURE_COUNT=0
    
    # Process each child node
    jq -r '.children[]? | @base64' <<< "$NODE" | while read -r CHILD_BASE64; do
        if [ -z "$CHILD_BASE64" ]; then
            continue
        fi
        
        CHILD=$(echo "$CHILD_BASE64" | base64 --decode)
        TYPE=$(jq -r '.type' <<< "$CHILD")
        
        # Handle nested test suite case
        if [ "$TYPE" == "testSuite" ]; then
            local NESTED_RESULTS
            NESTED_RESULTS=$(process_test_cases "$CHILD" "$PARENT_CLASS_NAME")
            
            # Extract test cases XML and counts from nested results
            local NESTED_XML=$(echo "$NESTED_RESULTS" | jq -r '.xml')
            local NESTED_COUNT=$(echo "$NESTED_RESULTS" | jq -r '.count')
            local NESTED_FAILURES=$(echo "$NESTED_RESULTS" | jq -r '.failures')
            
            TEST_CASES_XML="$TEST_CASES_XML$NESTED_XML"
            TEST_CASES_COUNT=$((TEST_CASES_COUNT + NESTED_COUNT))
            FAILURE_COUNT=$((FAILURE_COUNT + NESTED_FAILURES))
            continue
        fi
        
        # Skip if not a test case
        if [ "$TYPE" != "testCase" ]; then
            continue
        fi
        
        # Process test case
        TEST_CASES_COUNT=$((TEST_CASES_COUNT + 1))
        
        TEST_CASE_NAME=$(jq -r '.name' <<< "$CHILD")
        TEST_CASE_ID=$(jq -r '.identifier // ""' <<< "$CHILD")
        TEST_CASE_RESULT=$(jq -r '.result // "Unknown"' <<< "$CHILD")
        TEST_CASE_DURATION=$(jq -r '.duration // "0s"' <<< "$CHILD")
        
        # Extract class name from identifier
        CLASS_NAME=""
        if [ -n "$TEST_CASE_ID" ]; then
            CLASS_NAME=$(echo "$TEST_CASE_ID" | cut -d'/' -f1)
        fi
        
        # Use parent class name if class name is empty
        if [ -z "$CLASS_NAME" ]; then
            CLASS_NAME="$PARENT_CLASS_NAME"
        fi
        
        # Strip 's' from duration
        if [[ $TEST_CASE_DURATION == *s ]]; then
            TEST_CASE_DURATION=${TEST_CASE_DURATION%s}
        else
            TEST_CASE_DURATION=0
        fi
        
        # Start test case XML
        local TEST_CASE_XML="    <testcase name=\"$TEST_CASE_NAME\" classname=\"$CLASS_NAME\" time=\"$TEST_CASE_DURATION\">"
        
        # Process failure message if test failed
        if [ "$TEST_CASE_RESULT" != "Success" ]; then
            FAILURE_COUNT=$((FAILURE_COUNT + 1))
            
            # Extract failure message using a recursive function
            FAILURE_MESSAGE=""
            extract_failure_message() {
                local NODE="$1"
                local MSG=""
                
                # Check if this node is a failure message
                if [ "$(jq -r '.type' <<< "$NODE")" == "failureMessage" ]; then
                    MSG=$(jq -r '.name // ""' <<< "$NODE")
                    if [ -n "$MSG" ]; then
                        FAILURE_MESSAGE="$FAILURE_MESSAGE$MSG"
                    fi
                fi
                
                # Process children recursively
                jq -r '.children[]? | @base64' <<< "$NODE" 2>/dev/null | while read -r CHILD_BASE64; do
                    if [ -z "$CHILD_BASE64" ]; then
                        continue
                    fi
                    
                    local CHILD=$(echo "$CHILD_BASE64" | base64 --decode)
                    extract_failure_message "$CHILD"
                done
            }
            
            extract_failure_message "$CHILD"
            
            if [ -z "$FAILURE_MESSAGE" ]; then
                FAILURE_MESSAGE="Test failed"
            fi
            
            # XML escape the failure message
            FAILURE_MESSAGE=$(echo "$FAILURE_MESSAGE" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g; s/'"'"'/\&apos;/g')
            
            TEST_CASE_XML="$TEST_CASE_XML
      <failure message=\"$FAILURE_MESSAGE\" type=\"Failure\">$FAILURE_MESSAGE</failure>"
        fi
        
        # Close test case XML
        TEST_CASE_XML="$TEST_CASE_XML
    </testcase>"
        
        TEST_CASES_XML="$TEST_CASES_XML
$TEST_CASE_XML"
    done
    
    # Return results as JSON to handle output properly
    jq -n --arg xml "$TEST_CASES_XML" --arg count "$TEST_CASES_COUNT" --arg failures "$FAILURE_COUNT" '{
        xml: $xml,
        count: $count | tonumber,
        failures: $failures | tonumber
    }'
}

# Process each test plan
jq -r '.testNodes[] | select(.type=="testPlan") | @base64' <<< "$TEST_STRUCTURE" | while read -r TEST_PLAN_BASE64; do
    TEST_PLAN=$(echo "$TEST_PLAN_BASE64" | base64 --decode)
    TEST_PLAN_NAME=$(jq -r '.name' <<< "$TEST_PLAN")
    
    echo "Processing test plan: $TEST_PLAN_NAME"
    
    # Process each test bundle in this test plan
    jq -r '.children[] | select(.type=="unitTestBundle" or .type=="uiTestBundle") | @base64' <<< "$TEST_PLAN" | while read -r TEST_BUNDLE_BASE64; do
        TEST_BUNDLE=$(echo "$TEST_BUNDLE_BASE64" | base64 --decode)
        TEST_BUNDLE_NAME=$(jq -r '.name' <<< "$TEST_BUNDLE")
        
        echo "  Processing test bundle: $TEST_BUNDLE_NAME"
        
        # Process each test suite in this test bundle
        jq -r '.children[] | select(.type=="testSuite") | @base64' <<< "$TEST_BUNDLE" | while read -r TEST_SUITE_BASE64; do
            TEST_SUITE=$(echo "$TEST_SUITE_BASE64" | base64 --decode)
            TEST_SUITE_NAME=$(jq -r '.name' <<< "$TEST_SUITE")
            
            echo "    Processing test suite: $TEST_SUITE_NAME"
            
            # Process test cases recursively
            TEST_CASES_RESULT=$(process_test_cases "$TEST_SUITE" "$TEST_SUITE_NAME")
            TEST_CASES_XML=$(echo "$TEST_CASES_RESULT" | jq -r '.xml')
            TOTAL_TESTS=$(echo "$TEST_CASES_RESULT" | jq -r '.count')
            FAILURES=$(echo "$TEST_CASES_RESULT" | jq -r '.failures')
            
            # Calculate total duration of all test cases
            TOTAL_DURATION=0
            calculate_duration() {
                local NODE="$1"
                
                # Add duration if this is a test case
                if [ "$(jq -r '.type' <<< "$NODE")" == "testCase" ]; then
                    local DURATION=$(jq -r '.duration // "0s"' <<< "$NODE")
                    if [[ $DURATION == *s ]]; then
                        DURATION=${DURATION%s}
                        TOTAL_DURATION=$(echo "$TOTAL_DURATION + $DURATION" | bc 2>/dev/null || echo "$TOTAL_DURATION")
                    fi
                fi
                
                # Process children recursively
                jq -r '.children[]? | @base64' <<< "$NODE" 2>/dev/null | while read -r CHILD_BASE64; do
                    if [ -z "$CHILD_BASE64" ]; then
                        continue
                    fi
                    
                    local CHILD=$(echo "$CHILD_BASE64" | base64 --decode)
                    calculate_duration "$CHILD"
                done
            }
            
            calculate_duration "$TEST_SUITE"
            
            # Write test suite to XML file
            cat >> "$OUTPUT_PATH" << EOF
  <testsuite name="$TEST_SUITE_NAME" tests="$TOTAL_TESTS" failures="$FAILURES" errors="0" skipped="0" time="$TOTAL_DURATION" timestamp="$TIMESTAMP">
    <properties>
      <property name="testPlan" value="$TEST_PLAN_NAME"/>
      <property name="testBundle" value="$TEST_BUNDLE_NAME"/>
    </properties>$TEST_CASES_XML
  </testsuite>
EOF
        done
    done
done

# Close XML document
cat >> "$OUTPUT_PATH" << EOF
</testsuites>
EOF

echo "JUnit XML file created at $OUTPUT_PATH"
exit 0