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
git init -q --bare .remote.git && echo .remote.git >> .git/info/exclude
git remote add origin "$PWD/.remote.git" && git push -q origin main
git switch -q -c feature/SHOP-90-coupons
echo '// coupons' >> internal/discount/discount.go && git commit -qam "feat: coupons (SHOP-90)"
git switch -q -c feature/SHOP-92-coupon-expiry
echo '// expiry' >> internal/discount/discount.go
