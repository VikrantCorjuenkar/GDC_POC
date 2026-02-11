Write-Host "Executes all Apex Test Classes in a target org" -ForegroundColor green
$targetOrg = Read-Host -Prompt 'Enter Target Org alias name'

Remove-Item ./scanResults/ -Recurse -Force
mkdir /I ./scanResults

Write-Host "Executing test classes in $targetOrg" -ForegroundColor yellow
sf force apex test run --json --result-format json --test-level RunLocalTests --codecoverage -w 60 --target-org $targetOrg >> ./scanResults/apexTestResults.json
Write-Host "Finished executing test classes in $targetOrg. Check the results of test execution in ./scanResults/apexTestResults.json or directly in your Org" -ForegroundColor green
