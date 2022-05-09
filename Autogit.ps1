

##############################################################################
##                                                                          ##
##          AUTO CREATE, COMMIT and UPLOAD repositories from folders        ##
##                                                                          ##
##############################################################################


PARAM (
	[SWITCH]$Remote,
	[Parameter(Mandatory=$TRUE)][STRING]$Method,
	$Path =(Get-Location),
	[STRING]$Name,
	[STRING]$Username,
	[STRING]$Token,
	[SWITCH]$Force
)




FUNCTION Get-DirStats {

	PARAM (
		$Path
	)

	$fso = New-Object -com Scripting.FileSystemObject
	RETURN ( Get-ChildItem $Path -Force `
	| Select-Object @{l = 'Size'; e = { $fso.GetFolder($_.FullName).Size } }, Name `
	| Format-Table @{l = 'Size [MB]'; e = { '{0:N2} ' -f ($_.Size / 1MB) } }, Name )
}


FUNCTION Set-LocalRepository {
	
	[CmdletBinding(ConfirmImpact = 'High', SupportsShouldProcess = $true)]
	PARAM (
		[parameter(Mandatory=$TRUE)][STRING]$Method,
		[parameter(Mandatory=$TRUE)]$Path,
		[SWITCH]$Force
	)

	$location = Get-Location

	IF ( -not ( Test-Path $Path ) ) { RETURN "Wrong path `"${Path}`"" }

	SWITCH ( $Method ) {

		"Create" {
			$expression = "git init $Path"
			$operation = "Initialize local repository"
		}

		"Get" {
			$folderName = Split-Path $Path -Leaf 
			$isGitRepository = Test-Path "${Path}\.git"
			
			IF ( $isGitRepository ) {
				cd $Path
				$changes = git status --short
				cd $location

				$isAutoGit = Test-Path "${Path}\.git\.autogit"
				$isGitignoreExists = Test-Path "${Path}\.gitignore"

			} ELSE { $changes = $NULL }

			RETURN @{ 
				Name = $folderName;
				GitRepositoryInitialized = $isGitRepository; 
				AutoGitEnabled = $isAutoGit; 
				GitignoreExists = $isGitignoreExists;
				Changes = $changes; 
			}
		}

		"GetAll" { 
			FOREACH ( $folder in Get-ChildItem $Path -Directory -Force ) { 	##	should return an array of hashtables
				Set-LocalRepository Get $folder
			}
			RETURN
		}

		"Status" {
			$rep = Set-LocalRepository Get $Path

			IF ( $rep.GitRepositoryInitialized ) {
				Write-Host "  `u{e0a0} " -NoNewLine -ForegroundColor Green
				Write-Host "$($rep.Name):"

				Write-Host "`tautogit " -NoNewLine
				IF ( $rep.AutoGitEnabled ) { Write-Host "enabled" -ForegroundColor Green } 
				ELSE { Write-Host "disabled" -ForegroundColor Red }

				Write-Host "`t.gitignore " -NoNewLine
				IF ( $rep.GitignoreExists ) { Write-Host "exists" -ForegroundColor Green } 
				ELSE { Write-Host "not exists" -ForegroundColor Red }

				Write-Host "`tworking tree " -NoNewLine
				IF ( $rep.Changes ) { Write-Host "has changes" -ForegroundColor Yellow } 
				ELSE { Write-Host "is clean" }

			} ELSE { Write-Host "  `u{e613} $($rep.Name):" && Write-Host "`tNo repository" }

			Write-Host ""
			RETURN
		}

		"StatusAll" { 
			FOREACH ( $folder in Get-ChildItem $Path -Directory -Force ) {
				Set-LocalRepository ShowStatus $folder
			}
			RETURN
		}

		"EnableAutogit" {
			$expression = "New-Item ${Path}\.git\.autogit"
			$operation = "Create `".autogit`" file in `".git`" directory"
		}

		"Upload" {
			$rep = Set-LocalRepository Get $Path
			IF ( -not $rep ) { 
				Write-Host  "Can't get information about repository `"$($rep.Name)`""
				RETURN
			}

			IF ( -not $rep.GitRepositoryInitialized ) { 
				IF ( -not $Force ) {
					Write-Host "Folder `"$($rep.Name)`" doesn't have an initialized local repository:"
					Get-DirStats $Path
				}
				$result = Set-LocalRepository Create $Path -Force:$Force
				$result | Out-Null
				IF ( -not $result ) { 
					Write-Host "Skipping `"$($rep.Name)`"..." && Write-Host ""
					RETURN
				}
				$rep = Set-LocalRepository Get $Path
				Write-Host ""
			}
			
			IF ( -not $rep.Changes ) { 
				Write-Host "The repository `"$($rep.Name)`" has clean working tree. Skipping..." && Write-Host ""
				RETURN
			}
			
			IF ( -not $rep.AutoGitEnabled ) {
				Write-Host "The repository `"$($rep.Name)`" doesn't have `".autogit`" file in `".git`" directory."
				IF ( $Force -or -not ( Set-LocalRepository EnableAutogit $Path ) ) { 
					Write-Host "Skipping $($rep.Name)..." && Write-Host ""
					RETURN
				} 
				Write-Host ""			
			}

			IF ( ( -not $rep.GitignoreExists ) -and ( -not $Force ) ) {
				Write-Host "The repository `"$($rep.Name)`" does not contain a `".gitignore`" file:"
				Get-DirStats $Path
			}

			$result = Set-LocalRepository CommitAllChanges $Path -Force:$Force
			$result
			IF ( -not $result ) {
				Write-Host "Skipping `"$($rep.Name)`"..." && Write-Host ""
				RETURN
			}

			Write-Host ""
			RETURN
		}

		"UploadAll" { 
			Write-Host "Commiting changes in local repositories:"
			Get-DirStats $Path
			FOREACH ( $folder in Get-ChildItem $Path -Directory -Force ) {
				Set-LocalRepository Upload $folder -Force:$Force
			}
			RETURN
		}

		"CommitAllChanges" {
			$expression = "cd ${Path} && git add . && git commit -m `"auto-commit`" && cd ${location}"
			$operation = "Commit all changes in local repository"
		}

		"Delete" {
			IF ( -not ( Test-Path "${Path}\.git" ) ) { 
				RETURN "`"${Path}`" has no repository (`".git`" doesn't exists). Nothing to delete." 
			}
			$expression = "Remove-Item -Recurse -Force `"${Path}\.git`""
			$operation = "Delete local repository (`".git`" directory)"
		}

		DEFAULT { RETURN "Wrong method: ${Method}" }
	}

	IF ( $Force -or $PSCmdlet.ShouldProcess($Path, $operation) ) { Invoke-Expression $expression } 
	ELSE { RETURN }
}


FUNCTION Set-RemoteRepository {

	[CmdletBinding(ConfirmImpact = 'High', SupportsShouldProcess = $true)]
	PARAM (
		[Parameter(Mandatory=$TRUE)][STRING]$Method,
		[Parameter(Mandatory=$TRUE)][STRING]$Name,
		[Parameter(Mandatory=$TRUE)][STRING]$Username,
		[Parameter(Mandatory=$TRUE)][STRING]$Token,
		[SWITCH]$Force
	)

	$HTTP_query = @{ 
		Headers = @{ 
			Authorization = "token ${Token}"
			Accept = "application/vnd.github.v3+json" 
		} 
	}

	SWITCH ( $Method ) {
		"Create" {
			$operation = "Create new remote repository"
			$HTTP_query.Method = "POST"
			$HTTP_query.Uri = "https://api.github.com/user/repos"
			$HTTP_query.Body = "{ `"name`": `"$Name`", `"private`": true }"
		}
		"Get" {
			$HTTP_query.Method = "GET"
			$HTTP_query.Uri = "https://api.github.com/repos/${Username}/$Name"
			$Force = $TRUE
		}
		"Delete" {
			$operation = "Delete remote repository"	
			$HTTP_query.Method = "DELETE"
			$HTTP_query.Uri = "https://api.github.com/repos/${Username}/$Name"
		}
		DEFAULT { RETURN "Wrong method: ${Method}" }
	}

	IF ( $Force -or $PSCmdlet.ShouldProcess($Name, $operation) ) {
		TRY { $request = Invoke-WebRequest @HTTP_query } CATCH { $request = $PSItem.toString() | ConvertFrom-Json }
    	RETURN $request
	} ELSE { RETURN $FALSE }
}




IF ( $Remote ) {
	Set-RemoteRepository $Method $Name $Username $Token -Force:$Force
} ELSE {
	Set-LocalRepository $Method $Path -Force:$Force
}