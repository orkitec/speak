# Releasing

Releases are published to pub.dev by `.github/workflows/publish.yml` when a
version tag is pushed. It authenticates with GitHub's OIDC token through
pub.dev's automated publishing, so no secret is stored anywhere.

## One time

1. **Verified publisher.** On pub.dev, create the publisher `velorki.com`
   (pub.dev → your account → Create publisher). Google Search Console asks
   to verify the domain with a DNS TXT record on `velorki.com`; add it,
   then finish creating the publisher.
2. **First release by hand.** pub.dev only lets automated publishing be set
   up for a package that exists, so 0.1.0 goes out from a machine:
   ```sh
   flutter pub get
   dart pub publish --dry-run
   dart pub publish
   ```
   Then move the package to the publisher: pub.dev → `speak` → Admin →
   Transfer to publisher → `velorki.com`.
3. **Automated publishing.** pub.dev → `speak` → Admin → Automated
   publishing → Enable publishing from GitHub Actions:
   - Repository: `orkitec/speak`
   - Tag pattern: `v{{version}}`
   - Require GitHub Actions environment: on, environment `pub-dev`
4. **The `pub-dev` environment.** GitHub → `orkitec/speak` → Settings →
   Environments → New environment `pub-dev`. Add the maintainers as
   required reviewers, and under deployment branches and tags allow only
   tags matching `v*`.
5. **Allowed actions.** The publish job runs
   `dart-lang/setup-dart/.github/workflows/publish.yml`, which uses
   `dart-lang/setup-dart` and `flutter-actions/setup-flutter`. If the
   organisation only allows selected actions, add both (and the actions
   in `ci.yml`) under Settings → Actions → General.

## Every release

1. Bump `version` in `pubspec.yaml`, and add a `## <version>` section to
   `CHANGELOG.md`.
2. Run the checks (`flutter test`, `tool/web_test.sh`,
   `dart pub publish --dry-run`), and merge to `main`.
3. Tag the merge and push the tag:
   ```sh
   git tag v0.1.1
   git push origin v0.1.1
   ```
4. `publish.yml` checks that the tag matches `pubspec.yaml` and that
   `CHANGELOG.md` has the version, runs all of `ci.yml` (every platform and
   pana at 160), and then waits in the `pub-dev` environment. Approve it in
   the Actions tab; the package is published.

A failed run can be re-run from the Actions tab. A version, once on
pub.dev, cannot be published again: fix forward with the next version.
