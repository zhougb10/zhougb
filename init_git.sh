# Re-init git repo
cd /vol2/@appshare/com.dustinky.qwenpaw/.qwenpaw/workspaces/default/device-access-control
rm -rf .git
git init
git config user.email "zhougb10@users.noreply.github.com"
git config user.name "zhougb10"
git add -A
git commit -m "Initial release v1.0"
echo "=== git status ==="
git log --oneline
echo "=== files ==="
git ls-files