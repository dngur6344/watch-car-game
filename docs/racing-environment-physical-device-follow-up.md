# Racing Environment Physical-Device Follow-Up

Status: pending and nonblocking for the SG8 Simulator acceptance. These checks remain a release gate; until they pass, the racing environment must not be described as App Store release-ready on physical hardware.

- [ ] Run an iPhone 13 Release baseline drive for 15 minutes, including clear and storm weather.
- [ ] Run a latest-generation iPhone Release enhanced drive for 15 minutes, including clear and storm weather.
- [ ] Capture Metal allocation, thermal-state transitions, memory warnings, and resident-memory evidence for both runs.
- [ ] Confirm an enhanced-to-baseline downgrade preserves the active score, vehicle position, track composition, controls, and weather state.
- [ ] Pair an Apple Watch and complete a steering smoke during each Release run, including disconnect/fallback/reconnect behavior.
- [ ] Record the device models, OS versions, build revision, evidence paths, and pass/fail disposition before release sign-off.
