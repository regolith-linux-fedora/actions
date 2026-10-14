# Fedora workflows

Package repos in `regolith-linux-fedora` build, check and publish their Fedora
packages with four small workflow stubs. Each stub calls a reusable workflow in
this repo at `fedora/main`. Upstream's Debian workflows stay in the repo,
untouched.

## Install

From a checkout of this repo, on the package's `fedora/*` branch:

```shell
tools/install-fedora-workflows.sh ../<package-repo>
```

This copies `templates/fedora/*.yml` into `.github/workflows/`. Run it again to
pick up template changes; it only rewrites stubs that differ.

The package needs `<package>.spec` at the top of the repo, and an entry in
`regolith-linux-fedora/voulage` `stage/unstable/fedora/` whose `ref` is the
branch the stubs run on (usually `fedora/<upstream-branch>`).

## What runs when

| Stub | Trigger | Reusable workflow | Does |
|---|---|---|---|
| `fedora-test-pr.yml` | pull request into `fedora/**` | `fedora-test-pr.yml` | Per Fedora target and arch: version check, source RPM, mock build, `rpmlint`, upload RPMs; then install them into a clean `fedora:<release>` container with `regolith-unstable` enabled. |
| `fedora-publish-unstable.yml` | push to `fedora/**` | `fedora-publish-unstable.yml` | Builds the source RPM and submits it to COPR `@regolith/regolith-unstable` per chroot, waits for COPR, then records the commit in voulage's Fedora unstable manifests. |
| `fedora-prepare-release.yml` | push to `fedora/**` changing `*.spec` | `fedora-prepare-release.yml` | Reads `Version`/`Release` and creates tag `fedora/v<Version>-<Release>` and a GitHub release, and points voulage `stage/testing/fedora/**` at the tag. |
| `fedora-publish-testing.yml` | manual, on a `fedora/v*` tag | `fedora-publish-testing.yml` | Same as publish-unstable, into `@regolith/regolith-testing`. Manual until the testing promotion (Fedora Task 07-01) decides what goes to testing. |

The targets come from the package's entries in voulage: a release whose model
sets the package to `null`, or to another ref, is left out of the matrix. Each
target builds on its native runner (`amd64`: `ubuntu-24.04`, `arm64`:
`ubuntu-24.04-arm`) in `ghcr.io/regolith-linux-fedora/ci-fedora:<release>-<arch>`.
mock needs the container to be privileged.

**Rawhide is a canary.** Its jobs use `continue-on-error`: a failure shows as
a warning annotation and never fails the run.

### Checks

- **Version check** (`fedora-version-check`): the spec `Version` must equal the
  upstream version in `debian/changelog`, without epoch and Debian revision. A
  repo without `debian/changelog` passes.
- **rpmlint**: errors fail, warnings don't. Put known false positives in
  `<package>.rpmlintrc` next to the spec. rpmlint 2 reads TOML, e.g.
  `Filters = ["spelling-error .* Regolith"]`; the old `addFilter(...)` form is
  not reliable. Unknown words in `%description` (Regolith, sway, i3) are
  `spelling-error` *errors*.
- **Install test**: `dnf install` of every binary RPM except debuginfo and
  debugsource, then `rpm -V`.

## Secrets

Org secrets, available to all repositories (Fedora Task 00-03):

| Secret | Used by |
|---|---|
| `COPR_CONFIG` | publish workflows: the `~/.config/copr` block of a `@regolith` member |
| `PORT_BOT_TOKEN` | prepare-release (tags, releases, voulage commits) and the manifest update after publishing |

Without `PORT_BOT_TOKEN` a publish still succeeds, with a warning that voulage's
manifest was not updated, so voulage builds the commit again later. COPR
doesn't rebuild a version-release it already has.

## Reading failures

- **No Fedora target builds `<package>` from `<branch>`**: the matrix is
  empty. The branch isn't the `ref` of the package in voulage's Fedora
  unstable model.
- **`no-spec`**: the spec is missing or not at the top of the repo.
- **Version check**: bump the spec `Version`, or the `debian/changelog` entry,
  so they agree.
- **mock**: the build log is in the job output; the RPMs and mock logs are not
  uploaded when mock fails. Reproduce locally with the command in
  `regolith-linux-fedora/voulage` `docs/fedora.md`.
- **COPR**: `copr-cli` prints the build URL. The COPR build page has the
  per-chroot logs. A failed COPR build fails the job.

Re-run a failed job from the Actions tab ("Re-run failed jobs"). Publishing is
safe to re-run: a build COPR already has for the same version-release and
chroot is skipped.
