---
name: rails-best-practices
description: Rails best practices, antipatterns, and performance pitfalls. Covers controllers, models, views, routes, migrations, Active Record query optimization, timeout configuration, and common mistakes. Use when writing, reviewing, or refactoring Rails code. Sources: rails-bestpractices.com, rubocop/rails-style-guide, speedshop.co, ankane/the-ultimate-guide-to-ruby-timeouts.
---

# Rails Best Practices & Antipatterns

## Quick Antipattern Checklist

Run this first. Each item links to a detailed explanation in the supporting files.

- [ ] `default_scope` anywhere → remove it ([controllers-models.md](controllers-models.md))
- [ ] `after_save` with email/queue → move to `after_commit` ([controllers-models.md](controllers-models.md))
- [ ] `.count` before or after `.each` on same relation → use `.size` ([active-record.md](active-record.md))
- [ ] `.where` in an AR instance method → extract to filtered association ([active-record.md](active-record.md))
- [ ] `any?` before `each` on same relation → use `present?` or `.load.any?` ([active-record.md](active-record.md))
- [ ] `Time.now` or `Date.today` → use `Time.current` ([security-timeouts.md](security-timeouts.md))
- [ ] `rescue Exception` → use `rescue StandardError` ([security-timeouts.md](security-timeouts.md))
- [ ] No index on foreign keys → add `add_index` ([active-record.md](active-record.md))
- [ ] HTTP call with no timeout → add open + read timeouts ([security-timeouts.md](security-timeouts.md))
- [ ] `User.all.each` for 10k+ records → use `find_each` ([active-record.md](active-record.md))
- [ ] Instance variable in partial → pass as local ([controllers-models.md](controllers-models.md))
- [ ] Business logic in controller action → extract to service/model ([controllers-models.md](controllers-models.md))
- [ ] `save` return value ignored → use `save!` or handle false ([security-timeouts.md](security-timeouts.md))
- [ ] `update_attribute` in production code → use `update` (with validations) ([active-record.md](active-record.md))
- [ ] `enum` with array syntax → use hash syntax ([active-record.md](active-record.md))

---

## Topic Index

| Topic | File |
|---|---|
| Controllers (scope access, params, before_action, services) | [controllers-models.md](controllers-models.md) |
| Models (fat model rules, scopes, callbacks, law of demeter) | [controllers-models.md](controllers-models.md) |
| Active Record queries (N+1, count vs size, predicate methods) | [active-record.md](active-record.md) |
| AR model rules (enum, has_many, dependent, validations) | [active-record.md](active-record.md) |
| Views, Routes, Migrations | [security-timeouts.md](security-timeouts.md) |
| Security (rescue, strong params, Brakeman, Time.current) | [security-timeouts.md](security-timeouts.md) |
| Timeouts (DB, HTTP, Redis, Puma, Rack, ReDoS) | [security-timeouts.md](security-timeouts.md) |
| Performance (memoization, select, caching) | [security-timeouts.md](security-timeouts.md) |
