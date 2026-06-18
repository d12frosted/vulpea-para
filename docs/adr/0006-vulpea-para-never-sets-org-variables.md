# 6. vulpea-para never sets org variables automatically

Status: accepted

## Context

The agenda and capture experiences in a real config are personal: which custom commands appear in your dispatcher, in what order, your capture keys and templates, your agenda prefix format. If the library set `org-agenda-custom-commands` or `org-capture-templates` on load, it would either fight your existing config or quietly impose its own layout.

A survey of installed packages backs this up: across a hundred-plus packages, none set `org-agenda-custom-commands` or `org-capture-templates` for you. The norm is to ship building blocks and document an example. Equally common, though, is an opt-in `*-setup` function the user calls to wire convenience (for example `avy-setup`, or vulpea-journal's own `vulpea-journal-setup`).

## Decision

vulpea-para never sets an org variable on its own. It ships functions and data: the agenda command building blocks (`vulpea-para-agenda-cmd-*`), the skip functions and heading predicates, the category formatter, and the Org capture target and template functions. You assemble them into your own `org-agenda-custom-commands` and `org-capture-templates`; the README shows a complete example.

For convenience there is one opt-in entry point, `vulpea-para-setup-defaults`, which you may call to install a working default agenda and capture from those building blocks. It is never run automatically.

The one nuance: `org-agenda-files` is the agenda feature itself, a computed list rather than a layout choice, so `vulpea-para-agenda-files-update` sets it and `vulpea-para-agenda-mode` wires it. Both are opt-in.

## Consequences

- Nothing changes your org configuration unless you ask it to, by calling `vulpea-para-setup-defaults` or assembling the pieces yourself.
- Power users keep full control of the layout; newcomers get a one-line start.
- The command building blocks are autoloaded, so you can reference them from your config without loading the whole package.
