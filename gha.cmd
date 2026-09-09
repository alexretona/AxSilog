@echo off
REM Run gh as alexretona without changing the globally active gh account
REM (which stays megawidefoundationdashboard for the other project).
REM
REM The token is read from the Windows keyring at call time and lives only in
REM this transient cmd process — it is never written to disk and never leaks
REM back into the calling shell.
REM
REM   .\gha.cmd pr create --fill
REM   .\gha.cmd repo view
setlocal
for /f "usebackq delims=" %%t in (`gh auth token --user alexretona`) do set "GH_TOKEN=%%t"
if not defined GH_TOKEN (
  echo gha: could not read alexretona's token from the gh keyring. Run: gh auth login
  exit /b 1
)
gh %*
endlocal
