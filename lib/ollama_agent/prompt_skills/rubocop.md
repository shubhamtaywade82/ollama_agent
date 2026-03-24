# RuboCop alignment

<!-- Bundled stub: complements ruby_style.md (RuboCop follows the Ruby Style Guide). -->

- Prefer project `.rubocop.yml` and team conventions over generic rules.
- Run `bundle exec rubocop` (and `-a` / `-A` only when you understand the autocorrect).
- Resolve `rubocop:disable` comments sparingly; prefer fixing the underlying issue or a narrow cop-specific disable with a reason.
