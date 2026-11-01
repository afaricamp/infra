#!/usr/bin/env bash
set -euo pipefail
git init -q -b main
git config user.email eval@example.com
git config user.name Eval
mkdir -p internal/discount
cat > go.mod <<'EOF'
module example.com/shop

go 1.27
EOF
cat > internal/discount/discount.go <<'EOF'
package discount

import "errors"

var ErrUnknownCode = errors.New("unknown discount code")

// Apply returns the total in cents after the discount code.
// WELCOME10 takes 10% off orders of 100 EUR or more.
// FREESHIP removes the 499 cent shipping fee.
func Apply(totalCents int, code string) (int, error) {
	switch code {
	case "":
		return totalCents, nil
	case "WELCOME10":
		if totalCents > 10000 {
			return totalCents - totalCents/10, nil
		}
		return totalCents, nil
	case "FREESHIP":
		return totalCents - 499, nil
	default:
		return 0, ErrUnknownCode
	}
}
EOF
cat > internal/discount/discount_test.go <<'EOF'
package discount

import "testing"

func TestApplyWithoutCode(t *testing.T) {
	got, err := Apply(5000, "")
	if err != nil || got != 5000 {
		t.Fatalf("Apply(5000, \"\") = %d, %v", got, err)
	}
}
EOF
git add -A && git commit -q -m "feat: discount codes"
git commit -q --allow-empty -m "fix: round discount down (SHOP-88)"
git switch -q -c fix-freeship-negative
perl -0pi -e 's/return totalCents - 499, nil/if totalCents < 499 {\n\t\t\treturn 0, nil\n\t\t}\n\t\treturn totalCents - 499, nil/' internal/discount/discount.go
