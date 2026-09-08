# Security Policy

## Supported versions

The latest `main` branch is supported. Once releases begin, the newest minor
release will be supported with security fixes.

## Reporting a vulnerability

Please **do not** open a public issue for security vulnerabilities.
Instead, contact the maintainers privately with:

* A description of the issue and its potential impact
* Steps to reproduce (macOS version, hardware setup if display-related)
* Any suggested mitigation

You can expect an acknowledgement within 7 days and a fix or mitigation plan
as quickly as the issue allows. Please allow maintainers time to address the
issue before any public disclosure.

## Scope notes

DisplaySwitcher is fully local: it makes no network connections and stores
presets only in Application Support on your Mac. The most security-sensitive
surface is display reconfiguration — reports of the app leaving a system in an
unusable display state are treated as high priority.
