# Google TV profiles on an emulator without Google accounts, for testing Hearth.
#
# Google TV runs each profile but the owner's as a hidden Android profile user (type com.android.tv.profile) and keeps
# only the active one running; a kids profile's user carries Family Link's restrictions (set by its profile owner).
# This makes the same on a plain Google TV emulator (no root needed), so Hearth's ProfileUsers sees adult and kids
# profiles, switches, bedtime and its agents as on a TV. Google TV's own chooser doesn't list these users, so Hearth
# never learns their names or photos (its welcome card says "Setting up this profile...").
#
#   .\profiles.ps1 -Serial emulator-5564 add Kid -Kids     # new kids profile user (prints its id)
#   .\profiles.ps1 -Serial emulator-5564 add Grownup       # new adult profile user
#   .\profiles.ps1 -Serial emulator-5564 switch 10         # make user 10 the active profile (owner: switch 0)
#   .\profiles.ps1 -Serial emulator-5564 bedtime 10 on     # screen time up: block every app user 10 can open
#   .\profiles.ps1 -Serial emulator-5564 bedtime 10 off
#   .\profiles.ps1 -Serial emulator-5564 hearth 10         # put Hearth into user 10 (it runs there as an agent)
#   .\profiles.ps1 -Serial emulator-5564 list
#
# Needs build\supervisor.apk (build.ps1) for kids profiles and bedtime.
param(
    [Parameter(Mandatory = $true)] [string] $Serial,
    [Parameter(Mandatory = $true, Position = 0)] [ValidateSet('add', 'switch', 'bedtime', 'hearth', 'list')] [string] $Command,
    [Parameter(Position = 1)] [string] $Arg1,
    [Parameter(Position = 2)] [string] $Arg2,
    [switch] $Kids
)
$ErrorActionPreference = 'Stop'
$supervisor = 'com.example.hearthtest.supervisor'
$apk = "$PSScriptRoot\build\supervisor.apk"

function Dev { & adb.exe -s $Serial @args }
function Supervise([string] $user, [string[]] $extras) {
    Dev shell am broadcast --user $user -n "$supervisor/.Cmd" -a com.example.hearthtest.SUPERVISE @extras | Out-Null
}
function ProfileUsers {
    # "UserInfo{10:Kid:1010} running" -> 10, for every user but the owner
    (Dev shell pm list users) | Select-String 'UserInfo\{(\d+):' | ForEach-Object { $_.Matches[0].Groups[1].Value } |
            Where-Object { $_ -ne '0' }
}
function Launchables([string] $user) {
    (Dev shell cmd package query-activities --brief --user $user -a android.intent.action.MAIN -c android.intent.category.LEANBACK_LAUNCHER) |
            Select-String '^\s*([\w.]+)/' | ForEach-Object { $_.Matches[0].Groups[1].Value } |
            Where-Object { $_ -notin @('com.android.vending', 'com.thesiegs.hearth', $supervisor) } | Sort-Object -Unique
}

switch ($Command) {
    'add' {
        $out = Dev shell pm create-user --profileOf 0 --user-type com.android.tv.profile $Arg1
        $user = ([regex]'id (\d+)').Match("$out").Groups[1].Value
        if (-not $user) { throw "create-user failed: $out" }
        if ($Kids) {
            if (-not (Test-Path $apk)) { throw "build $apk first (build.ps1)" }
            Dev install -t --user $user $apk | Out-Null
            Dev shell dpm set-profile-owner --user $user "$supervisor/.Admin" | Out-Null
            Dev shell am start-user -w $user | Out-Null
            Supervise $user @('--ez', 'supervised', 'true')
            Dev shell am stop-user -f $user | Out-Null
        }
        Write-Output $user
    }
    'switch' {
        # Like Google TV: stop the other profile users first, then start the new one
        foreach ($user in ProfileUsers) { if ($user -ne $Arg1) { Dev shell am stop-user -f $user | Out-Null } }
        if ($Arg1 -ne '0') { Dev shell am start-user -w $Arg1 | Out-Null }
    }
    'bedtime' {
        $packages = (Launchables $Arg1) -join ','
        if ($Arg2 -eq 'on') { Supervise $Arg1 @('--es', 'suspend', $packages) } else { Supervise $Arg1 @('--es', 'unsuspend', $packages) }
    }
    'hearth' {
        Dev shell pm install-existing --user $Arg1 com.thesiegs.hearth
    }
    'list' {
        Dev shell pm list users
    }
}
