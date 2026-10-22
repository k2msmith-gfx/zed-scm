;; Every form indents its contents one level. This is all Zed's syntax-driven
;; indenter can express: there is no per-head indent amount, so a `let`'s
;; bindings do not align under the opening paren the way `scheme-mode`'s
;; `scheme-indent-function` aligns them. See docs/plan.md, Z1 limitations.
(_ "(" ")") @indent
(_ "[" "]") @indent
