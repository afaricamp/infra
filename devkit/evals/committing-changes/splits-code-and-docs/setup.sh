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
printf '# Shop\n\nDiscount codez live in internal/discount.\n' > README.md
git add README.md && git commit -q -m "docs: readme"
git switch -q -c fix/SHOP-91-welcome-threshold
sed -i.bak 's/totalCents > 10000/totalCents >= 10000/' internal/discount/discount.go && rm internal/discount/discount.go.bak
cat >> internal/discount/discount_test.go <<'EOF'

func TestWelcomeAtThreshold(t *testing.T) {
	got, _ := Apply(10000, "WELCOME10")
	if got != 9000 {
		t.Fatalf("got %d", got)
	}
}
EOF
sed -i.bak 's/codez/codes/' README.md && rm README.md.bak
