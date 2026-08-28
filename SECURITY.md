# Security

Report vulnerabilities privately through GitHub Security Advisories for this repository. Do not include secrets or customer terminal output in a public issue.

`shellfie generate` never executes YAML content. `shellfie run` and `shellfie record` intentionally execute commands from version 2 session files with the invoking user's permissions. Review session files before running them, use `redact` for sensitive output, and prefer cassette replay in untrusted documentation builds.

Security fixes are supported on the latest released version.
