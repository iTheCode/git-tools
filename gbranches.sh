#!/bin/bash

# gbranches - Git Branch Creation and Propagation Utility
# Creates feature branches from multiple base branches (develop, testing, staging, master)
# with options to propagate changes, push branches, and prepare for PRs
# Usage: gbranches feature-name [options]

set -e  # Exit immediately if a command exits with a non-zero status

# Function to display usage information
function show_usage() {
    echo "Usage: gbranches <feature-name> [options]"
    echo ""
    echo "Options:"
    echo "  -c, --create-only    Only create branches without propagating changes"
    echo "  -p, --push           Push branches to remote after creation/propagation"
    echo "  -m, --message        Commit message for changes (required with -a)"
    echo "  -a, --apply-changes  Apply changes to all branches (requires -m)"
    echo "  -pr, --create-pr     Create pull requests for each branch with the given title"
    echo "  -b, --pr-body        Pull request body/description (use with -pr)"
    echo "  -h, --help           Show this help message"
    echo ""
    echo "Base branches hierarchy (bottom-up):"
    echo "  master (PROD) → staging (STG) → testing (QA) → develop (DEV)"
    echo ""
    echo "Each base branch respect their own history lane."
    echo "Changes are worked on master base branch and use cherry pick to propagate to other branches."
    echo ""
    echo "Example:"
    echo "  gbranches CDC-123-card-feature-name -p -a -m \"Add user authentication feature\""
    echo "  Creates branches, applies changes, and pushes to remote"
    echo ""
    echo "  gbranches CDC-123-card-feature-name -p -pr \"Implements user authentication feature\""
    echo "  Creates branches, pushes to remote, and creates PRs with the provided title"
    echo ""
    echo "  gbranches CDC-123-card-feature-name -p -pr \"Implements user authentication feature\" -b \"Implements user authentication feature\""
    echo "  Creates branches, pushes to remote, and creates PRs with custom PR title and body"
    echo ""
    echo "Important: "
    echo "  PR create option needs to be authenticated with GitHub using 'gh auth login'"
}

# Function to validate that we're in a git repository
function validate_git_repo() {
    if ! git rev-parse --is-inside-work-tree &> /dev/null; then
        echo "Error: Not in a git repository"
        exit 1
    fi

    # Check if we have a valid remote named 'origin'
    if ! git remote get-url origin &> /dev/null; then
        echo "Error: No remote named 'origin' found"
        exit 1
    fi
}

# Function to check if a branch exists (local or remote)
function branch_exists() {
    # Check if it exists as a local branch
    if git show-ref --verify --quiet refs/heads/$1; then
        return 0  # Branch exists locally
    fi

    # Check if it exists as a remote branch
    if git ls-remote --heads origin $1 | grep -q $1; then
        return 0  # Branch exists on remote
    fi

    return 1  # Branch doesn't exist
}

# Function to check if there are uncommitted changes
function has_uncommitted_changes() {
    if ! git diff-index --quiet HEAD --; then
        return 0  # There are changes
    else
        return 1  # No changes
    fi
}

# Function to check if GitHub CLI is installed
function check_gh_cli() {
    if ! command -v gh &> /dev/null; then
        echo "GitHub CLI (gh) is not installed. Please install it to use the PR creation feature."
        echo "Installation instructions: https://github.com/cli/cli#installation"
        return 1
    fi

    # Check if user is authenticated with GitHub
    if ! gh auth status &> /dev/null; then
        echo "Not authenticated with GitHub. Please run 'gh auth login' first."
        return 1
    fi

    return 0
}

# Function to ensure a branch is checked out locally
function ensure_branch_local() {
    local branch_name=$1

    # Check if branch exists locally
    if git show-ref --verify --quiet refs/heads/$branch_name; then
        # Checkout the branch
        git checkout "$branch_name"

        # Pull the latest changes
        git pull origin "$branch_name" --ff-only
    else
        # Checkout the remote branch
        git checkout -b "$branch_name" origin/"$branch_name"
    fi
}

# Function to create feature branches
function create_feature_branches() {
    local feature_name=$1
    local base_branches=("develop" "testing" "staging" "master")
    local branch_prefixes=("DEV" "QA" "STG" "PROD")
    declare -a created_branches=()

    # Store the current branch to return to it later
    local master_branch="PROD_${feature_name}"
    local current_branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "detached")

    echo "Creating feature branches for: $feature_name"
    echo "----------------------------------------"

    # Loop through each base branch
    for i in "${!base_branches[@]}"; do
        local base_branch=${base_branches[$i]}
        local prefix=${branch_prefixes[$i]}
        local new_branch="${prefix}_${feature_name}"

        echo "Processing: $base_branch -> $new_branch"

        # Check if the new branch already exists
        if branch_exists "$new_branch"; then
            echo "⚠️  Branch $new_branch already exists. Skipping creation."
            created_branches+=("$new_branch")
            continue
        fi

        # Check if the base branch exists
        if ! branch_exists "$base_branch"; then
            echo "⚠️  Base branch $base_branch doesn't exist. Skipping."
            continue
        fi

        # Ensure base branch is checked out locally
        ensure_branch_local "$base_branch"

        # Create the new branch
        echo "Creating branch $new_branch..."
        git checkout -b "$new_branch"

        echo "✅ Successfully created $new_branch from $base_branch"
        created_branches+=("$new_branch")
        echo ""
    done

    echo "----------------------------------------"
    echo "Summary of created branches:"
    for branch in "${created_branches[@]}"; do
        echo "✅ $branch"
    done


    git checkout "$master_branch"

    # Save created branches to a global variable
    CREATED_BRANCHES=("${created_branches[@]}")
}

# Function to propagate changes across branches using cherry-pick
function propagate_changes() {
    local branches=($@)
    local commit_message="$COMMIT_MESSAGE"

    # Exit if no branches to process
    if [[ ${#branches[@]} -eq 0 ]]; then
        echo "No branches to propagate changes to."
        return
    fi

    echo ""
    echo "Propagating changes across branches using cherry-pick"
    echo "----------------------------------------"

    # Sort branches in the desired order (master → staging → testing → develop)
    # Starting with master (PROD) and propagating to less stable branches
    local sorted_branches=()
    for prefix in "PROD" "STG" "QA" "DEV"; do
        for branch in "${branches[@]}"; do
            if [[ $branch == ${prefix}_* ]]; then
                sorted_branches+=("$branch")
                break
            fi
        done
    done

    local remote_branches=("master" "staging" "testing" "develop")

    # If no changes to apply (create only mode), return
    if [[ "$APPLY_CHANGES" != "true" ]]; then
        return
    fi

    # Check if there are changes to commit on the current branch
    if ! has_uncommitted_changes; then
        echo "No changes to commit. Making a dummy change for demonstration..."
        echo "# Automated change by gbranches script" >> README.md
    fi

    # Start with the most stable branch (usually PROD/master)
    local first_branch="PROD_${FEATURE_NAME}"
    if [[ -n "$first_branch" ]]; then
        echo "Starting with branch: $first_branch"
        git checkout "$first_branch"

        # Check if there are changes to commit
        if has_uncommitted_changes; then
            echo "Committing changes on $first_branch..."
            git commit -m "$commit_message"
        fi

        local commit_hash=$(git rev-parse HEAD)
        echo "✅ Committed changes to $first_branch (Commit: ${commit_hash:0:8})"

        # Now propagate to other branches using cherry-pick
        for ((i=1; i<${#sorted_branches[@]}; i++)); do
            local current_branch=${sorted_branches[$i]}
            local remote_branch=${remote_branches[$i]}

            echo "Cherry-picking to: $current_branch (from commit: ${commit_hash:0:8})"
            git checkout "$current_branch"
            git fetch
            if git pull origin "$remote_branch"; then
                echo "✅ Successfully pulled changes from $remote_branch"
            else
                echo "⚠️  Conflicts with $remote_branch as recomendation create a new branch and start as a new feature"
            fi

            # Try to cherry-pick the commit
            if [[ "$first_branch" != "$current_branch" ]] && git cherry-pick "$commit_hash"; then
                echo "✅ Successfully cherry-picked changes to $current_branch"
            else
                # If the commit is already or empty in the branch, skip the cherry-pick
                if git commit --allow-empty; then
                    echo "✅ Successfully skipped cherry-pick to $current_branch"
                else
                    echo "⚠️  Cherry-pick conflicts in $current_branch"
                    echo "To resolve manually:"
                    echo "  1. Fix the conflicts in the files"
                    echo "  2. git add <resolved-files>"
                    echo "  3. git cherry-pick --continue"
                    echo "  4. Or to abort: git cherry-pick --abort"
                    echo "Manual intervention required - stopping propagation"
                    return 1
                fi
            fi
        done
    fi

    echo "----------------------------------------"
    echo "Successfully propagated changes to all branches using cherry-pick"
    git checkout "$first_branch"
}

# Function to push branches to remote
function push_branches() {
    local branches=($@)

    # Exit if no branches to process
    if [[ ${#branches[@]} -eq 0 ]]; then
        echo "No branches to push."
        return
    fi

    echo ""
    echo "Pushing branches to remote"
    echo "----------------------------------------"

    for branch in "${branches[@]}"; do
        echo "Pushing $branch..."
        git checkout "$branch"
        git push -u origin "$branch"
        echo "✅ Successfully pushed $branch to remote"
    done

    echo "----------------------------------------"
    echo "All branches pushed to remote"
}

# Function to create pull requests
function create_pull_requests() {
    local branches=($@)
    local feature_name="$FEATURE_NAME"
    local pr_title="$PR_TITLE"
    local pr_body="$PR_BODY"

    # Exit if no branches to process
    if [[ ${#branches[@]} -eq 0 ]]; then
        echo "No branches to create PRs for."
        return
    fi

    # Check if GitHub CLI is installed and authenticated
    if ! check_gh_cli; then
        return 1
    fi

    echo ""
    echo "Creating pull requests"
    echo "----------------------------------------"


    for branch in "${branches[@]}"; do
        # Extract the prefix (DEV, QA, STG, PROD)
        local prefix=$(echo "$branch" | cut -d'_' -f1)
        local card_number=$(echo "$feature_name" | cut -d'-' -f1,2)

        if [[ $prefix == "DEV" ]]; then
            local target_branch="develop"
            local label=""
        elif [[ $prefix == "QA" ]]; then
            local target_branch="testing"
            local label="--label qa"
        elif [[ $prefix == "STG" ]]; then
            local target_branch="staging"
            local label="--label stg"
        elif [[ $prefix == "PROD" ]]; then
            local target_branch="master"
            local label="--label production"
        fi

        # Construct PR title based on prefix and provided title
        local full_pr_title="[$prefix] $card_number: $pr_title"

        echo "Creating PR for $branch → $target_branch"
        git checkout "$branch"

        # Create the PR using GitHub CLI
        # i wanna add a label to the PR
        if gh pr create --base "$target_branch" --head "$branch" --title "$full_pr_title" --body "$pr_body" $label; then
            echo "✅ Successfully created PR for $branch"

            # Get the PR URL and display it
            local pr_url=$(gh pr view --json url -q .url)
            echo "   PR URL: $pr_url"
        else
            echo "⚠️  Failed to create PR for $branch"
        fi
    done

    echo "----------------------------------------"
    echo "PR creation completed"

    git checkout master
}

# Parse command line arguments
FEATURE_NAME=""
CREATE_ONLY=false
PUSH_BRANCHES=false
APPLY_CHANGES=false
CREATE_PR=false
PR_TITLE=""
PR_BODY=""
COMMIT_MESSAGE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -c|--create-only)
            CREATE_ONLY=true
            shift
            ;;
        -p|--push)
            PUSH_BRANCHES=true
            shift
            ;;
        -a|--apply-changes)
            APPLY_CHANGES=true
            shift
            ;;
        -pr|--create-pr)
            CREATE_PR=true
            PUSH_BRANCHES=true  # PR creation requires pushing
            if [[ -n "$2" && ! "$2" =~ ^- ]]; then
                PR_TITLE="$2"
                shift 2
            else
                echo "Error: -pr/--create-pr requires a PR title"
                show_usage
                exit 1
            fi
            ;;
        -m|--message)
            if [[ -n "$2" && ! "$2" =~ ^- ]]; then
                COMMIT_MESSAGE="$2"
                shift 2
            else
                echo "Error: -m/--message requires a commit message"
                show_usage
                exit 1
            fi
            ;;
        -b|--pr-body)
            if [[ -n "$2" && ! "$2" =~ ^- ]]; then
                PR_BODY="$2"
                shift 2
            else
                echo "Error: -b/--pr-body requires a PR body"
                show_usage
                exit 1
            fi
            ;;
        *)
            if [[ -z "$FEATURE_NAME" ]]; then
                FEATURE_NAME="$1"
                shift
            else
                echo "Unknown option: $1"
                show_usage
                exit 1
            fi
            ;;
    esac
done

# Validate inputs
if [[ -z "$FEATURE_NAME" ]]; then
    echo "Error: Feature name is required"
    show_usage
    exit 1
fi

if [[ "$APPLY_CHANGES" == "true" && -z "$COMMIT_MESSAGE" ]]; then
    echo "Error: Commit message (-m) is required with apply changes (-a)"
    show_usage
    exit 1
fi

if [[ "$CREATE_PR" == "true" && -z "$PR_TITLE" ]]; then
    echo "Error: PR title is required with create PR (-pr)"
    show_usage
    exit 1
fi

if [[ "$CREATE_PR" == "true" && -z "$PR_BODY" ]]; then
    # Set a default PR body if not provided
    PR_BODY="Pull request for $FEATURE_NAME"
    echo "Note: Using default PR description. You can specify one with -b option."
fi

# Main script execution

# Validate we're in a git repository
validate_git_repo

# Check for uncommitted changes if not applying changes
if [[ "$APPLY_CHANGES" != "true" ]] && has_uncommitted_changes; then
    echo "⚠️  Warning: You have uncommitted changes"
    read -p "Do you want to continue anyway? (y/n): " continue_anyway
    if [[ "$continue_anyway" != "y" ]]; then
        echo "Operation cancelled."
        exit 0
    fi
fi

# Remember current branch
CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "detached")


BRANCHES=()
for prefix in "DEV" "QA" "STG" "PROD"; do
    BRANCHES+=("${prefix}_${FEATURE_NAME}")
done

# Create the feature branches (stores result in CREATED_BRANCHES variable)
if [[ "$CREATE_ONLY" == "true" ]]; then 
    create_feature_branches "$FEATURE_NAME"
fi

# Apply changes if requested
if [[ "$APPLY_CHANGES" == "true"  ]]; then
    propagate_changes "${BRANCHES[@]}"
fi

# Push branches if requested
if [[ "$PUSH_BRANCHES" == "true" ]]; then
    push_branches "${BRANCHES[@]}"
fi

# Create PRs if requested
if [[ "$CREATE_PR" == "true" && ${#BRANCHES[@]} -gt 0 ]]; then
    create_pull_requests "${BRANCHES[@]}"
fi

echo ""
echo "Done! 🎉"