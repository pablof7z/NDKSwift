# Olas E2E Tests (Maestro)

End-to-end UI tests for Olas using [Maestro](https://maestro.mobile.dev/).

## Prerequisites

1. Install Maestro:
   ```bash
   curl -Ls "https://get.maestro.mobile.dev" | bash
   ```

2. Build the app for simulator:
   ```bash
   xcodebuild -project Olas.xcodeproj -scheme Olas -sdk iphonesimulator -configuration Debug build
   ```

3. Boot a simulator:
   ```bash
   xcrun simctl boot "iPhone 16"
   ```

## Running Tests

### Run all tests
```bash
cd Olas
maestro test maestro/flows/
```

### Run a specific flow
```bash
maestro test maestro/flows/01_onboarding.yaml
```

### Run with debug output
```bash
maestro test --debug maestro/flows/01_onboarding.yaml
```

## Test Flows

| Flow | Description | Prerequisites |
|------|-------------|---------------|
| `01_onboarding.yaml` | Tests onboarding screen and auth buttons | Fresh install |
| `02_feed_browsing.yaml` | Tests feed navigation and scrolling | Logged in |
| `03_content_creation.yaml` | Tests create post flow (no publish) | Logged in |
| `04_wallet.yaml` | Tests wallet tab and setup | Logged in |
| `05_profile.yaml` | Tests profile and settings navigation | Logged in |
| `06_settings.yaml` | Tests all settings sections | Logged in |

## CI Integration

For CI, you can use Maestro Cloud or run locally:

```yaml
# Example GitHub Actions step
- name: Run Maestro Tests
  run: |
    maestro test maestro/flows/ --format junit --output test-results.xml
```

## Environment Variables

For tests requiring login:
- `TEST_NSEC`: Test account nsec (keep secret!)
- `TEST_NPUB`: Test account npub

## Screenshots

Screenshots are saved to `.maestro/screenshots/` on test failure.

## Troubleshooting

### App not found
Make sure the app is installed on the simulator:
```bash
xcrun simctl install booted path/to/Olas.app
```

### Element not found
- Increase wait timeouts in the flow
- Check accessibility identifiers match
- Run `maestro studio` to inspect the UI hierarchy
