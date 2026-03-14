#!/bin/bash
# =============================================================================
# Generate Traffic for the OTel Demo
# =============================================================================
# Sends various requests to the Order Service to generate traces.
# Includes: normal orders, high quantities (stock errors), varied amounts.
# =============================================================================

set -euo pipefail

BASE_URL="${1:-http://localhost:8080}"
NUM_REQUESTS="${2:-20}"

# Ensure port-forward to order-service is active
if ! curl -s --max-time 1 "$BASE_URL/health" > /dev/null 2>&1; then
  echo "📡 Starting port-forward to order-service..."
  kubectl port-forward svc/order-service -n demo 8080:8080 &
  PF_PID=$!
  sleep 3
  echo "   Port-forward started (PID $PF_PID)"
fi

ITEMS=("laptop" "phone" "tablet" "headphones" "keyboard" "rare-item")

echo "🔭 Generating $NUM_REQUESTS orders against $BASE_URL..."
echo ""

success=0
errors=0

for i in $(seq 1 "$NUM_REQUESTS"); do
  item=${ITEMS[$((RANDOM % ${#ITEMS[@]}))]}
  quantity=$((RANDOM % 5 + 1))
  amount=$((RANDOM % 2000 + 10))

  response=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/orders" \
    -H "Content-Type: application/json" \
    -d "{\"item\": \"$item\", \"quantity\": $quantity, \"amount\": $amount}" 2>/dev/null)

  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | head -1)

  if [[ "$http_code" =~ ^2 ]]; then
    echo "  ✅ Order $i: $quantity× $item (\$$amount) → HTTP $http_code"
    ((success++))
  else
    echo "  ❌ Order $i: $quantity× $item (\$$amount) → HTTP $http_code"
    ((errors++))
  fi

  # Small delay to spread traces
  sleep 0.2
done

echo ""
echo "=================================================="
echo "📊 Results: $success successful, $errors errors out of $NUM_REQUESTS orders"
echo ""
echo "🔍 Now check Jaeger: http://localhost:16686"
echo "   Select service: order-service → Find Traces"
echo "=================================================="
