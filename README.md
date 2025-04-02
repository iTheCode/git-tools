# gbranches - Git Branch Creation and Propagation Utility

`gbranches` is a powerful bash utility for managing feature branches across multiple environments in a Git repository. It simplifies working with feature branches across your development pipeline, from development to production.

## Features

- **Multi-environment Branch Creation**: Create feature branches from develop, testing, staging, and master branches
- **Consistent Naming**: Automatically apply standardized naming prefixes (DEV, QA, STG, PROD)
- **Change Propagation**: Apply changes once and propagate to all branches using cherry-pick
- **Remote Integration**: Push branches to remote repositories
- **PR Automation**: Create pull requests for each branch with custom titles and descriptions
- **History Preservation**: Respects each branch's history lane

## Installation

1. Download the script:
   ```bash
   curl -o gbranches https://raw.githubusercontent.com/iTheCode/git-tools/main/gbranches.sh
   ```

2. Make it executable:
   ```bash
   chmod +x gbranches
   ```

3. Move it to a directory in your PATH:
   ```bash
   sudo mv gbranches /usr/local/bin/
   ```

4. Install gh:
   - Mac:
   ```bash
   brew install gh
   ```
   - Linux:
   ```bash
   sudo apt install gh
   ```

5. Authenticate with GitHub:
   ```bash
   gh auth login
   ```

## Branch Hierarchy

The script works with the following branch hierarchy (bottom-up):
```
master (PROD) → staging (STG) → testing (QA) → develop (DEV)
```

Changes are typically made on the master branch first and then propagated to other branches using cherry-pick to maintain independent history lanes.

## Usage

```bash
gbranches <feature-name> [options]
```

### Options

| Option | Description |
|--------|-------------|
| `-c, --create-only` | Only create branches without propagating changes |
| `-p, --push` | Push branches to remote after creation/propagation |
| `-m, --message` | Commit message for changes (required with -a) |
| `-a, --apply-changes` | Apply changes to all branches (requires -m) |
| `-pr, --create-pr` | Create pull requests for each branch |
| `-b, --pr-body` | Pull request body/description (use with -pr) |
| `-h, --help` | Show help message |

### Examples

1. **Create branches only**:
   ```bash
   gbranches CDC-123-card-feature-name
   ```

2. **Create branches and push to remote**:
   ```bash
   gbranches CDC-123-card-feature-name -p
   ```

3. **Create branches, apply changes, and push to remote**:
   ```bash
   gbranches CDC-123-card-feature-name -p -a -m "Add user authentication feature"
   ```

4. **Create branches, push to remote, and create PRs**:
   ```bash
   gbranches CDC-123-card-feature-name -p -pr -b "Implements user authentication feature"
   ```

## PR Creation

To use the PR creation feature, you must:

1. Have the GitHub CLI (`gh`) installed
2. Be authenticated with GitHub using `gh auth login`

The script will create PRs with titles formatted as: `[PREFIX] feature-name`

## Workflow Example

Here's a typical workflow:

1. **Start a new feature**:
   ```bash
   gbranches CDC-123-login-feature
   ```

2. **Make your changes on the PROD branch first**:
   ```bash
   git checkout PROD_CDC-123-login-feature
   # Make code changes...
   ```

3. **Apply changes and create PRs**:
   ```bash
   gbranches CDC-123-login-feature -a -m "Implement login functionality" -p -pr -b "This PR adds login functionality with OAuth support"
   ```

4. **Check all created PRs on GitHub and proceed with the review process**

## Troubleshooting

- **Cherry-pick conflicts**: If conflicts occur during propagation, the script will guide you through the resolution process
- **Missing branches**: The script will skip branches that don't exist and continue with the ones that do
- **PR creation issues**: Ensure you're authenticated with GitHub using `gh auth login`

## Dependencies

- Git
- GitHub CLI (gh) - for PR creation feature

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
