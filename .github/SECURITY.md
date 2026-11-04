# Security policy

## Existing tooling

GitHub Actions runs [the comprehensive test suite](../docs/reference/release-pipeline.md)
on every push. It includes hostile documents, in Org and Markdown, which must run no code
and fetch nothing from the network, and hostile requests to the local server. No
vulnerability scanner runs on this repository, and its vendored files are updated by hand.

[The README](../README.md#security) describes the security model.

## Supported versions

Only the latest [release](https://github.com/piotr-yuxuan/imprimeur/releases) is supported.
This package is pre-release, so a fix reaches no earlier version.

## Reporting a vulnerability

Open an issue, or contact the [code owners](./CODEOWNERS.yml) on social media.
