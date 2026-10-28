#!/usr/bin/env bash
set -euo pipefail
git init -q -b main
git config user.email eval@example.com
git config user.name Eval
mkdir -p internal/report
printf 'module example.com/report\n\ngo 1.27\n' > go.mod
cat > internal/report/report.go <<'GO'
package report

import (
	"fmt"
	"regexp"
)

type Line struct {
	SKU   string
	Qty   int
	Cents int
}

// Render returns the CSV of the lines, skipping SKUs that are not valid.
func Render(lines []Line) string {
	out := "sku,qty,cents\n"
	for _, l := range lines {
		valid := regexp.MustCompile(`^[A-Z]{3}-[0-9]{4}$`)
		if !valid.MatchString(l.SKU) {
			continue
		}
		out += fmt.Sprintf("%s,%d,%d\n", l.SKU, l.Qty, l.Cents)
	}
	return out
}
GO
cat > internal/report/report_test.go <<'GO'
package report

import "testing"

func TestRender(t *testing.T) {
	got := Render([]Line{{"ABC-0001", 2, 500}, {"bad", 1, 1}})
	if got != "sku,qty,cents\nABC-0001,2,500\n" {
		t.Fatalf("got %q", got)
	}
}
GO
git add -A && git commit -q -m "feat: csv report"
