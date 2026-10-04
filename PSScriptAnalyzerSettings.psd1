# PSScriptAnalyzer settings for John's Toolkit
# Rules turned off below are conventions for reusable PowerShell modules, not for a GUI application.
# Every other rule (Error and Warning) must stay at zero findings: tests\Run-Tests.ps1 checks it.
@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # A GUI app with its own confirmation dialogs; -WhatIf/-Confirm would never be used
        'PSUseShouldProcessForStateChangingFunctions'
        # Coloured console output in the classic mode and the build/test scripts is intended
        'PSAvoidUsingWriteHost'
        # Names like Get-PcSpecs / Get-WslDisks read better in this code base
        'PSUseSingularNouns'
        'PSUseApprovedVerbs'
        # "Best effort" reads (no battery, no TPM, file in use...) must never stop the app; the pattern is deliberate
        'PSAvoidUsingEmptyCatchBlock'
        # The app is split into files that share variables (00-State.ps1 defines what the pages use)
        # and background-task script blocks receive values used by the dot-sourced engine
        'PSUseDeclaredVarsMoreThanAssignments'
        'PSReviewUnusedParameter'
        # Test-Connection 1.1.1.1 is the deliberate "is the internet up?" check of the network repair
        'PSAvoidUsingComputerNameHardcoded'
        # Write-Log is not a cmdlet in Windows PowerShell 5.1 (the app's target); the tests replace
        # Start-Process/Stop-Process/Restart-Computer on purpose so nothing real happens
        'PSAvoidOverwritingBuiltInCmdlets'
    )
}
