// Semantic-release configuration.
//
// The runner image is versioned by git tags, not npm: the version lives in the
// tag and the GitHub release created here. build.yml then publishes the image
// with the matching docker.io tag and uploads the digest asset to the release.
//
// Toolchain bumps (dependabot "build(deps):" commits) are patch releases so
// every merged change republishes a versioned image; docs/ci/chore changes do
// not create releases.
//
// The default (angular) preset is used so no plugin packages beyond the ones
// bundled with semantic-release are required.
module.exports = {
  branches: ["main"],
  tagFormat: "v${version}",
  plugins: [
    [
      "@semantic-release/commit-analyzer",
      {
        releaseRules: [
          { type: "build", release: "patch" },
          { type: "ci", release: false },
          { type: "docs", release: false },
          { type: "chore", release: false },
        ],
      },
    ],
    ["@semantic-release/release-notes-generator"],
    ["@semantic-release/github", {}],
  ],
};
