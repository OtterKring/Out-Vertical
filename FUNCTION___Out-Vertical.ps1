<#
.SYNOPSIS
    Out-Vertical

    Think of it as Format-Table, turned 90° counterclockwise.

.DESCRIPTION
    Out-Vertical takes any number of objects and puts them on display in columns next to each other, with all properties merged and sorted as the first column
    Each output line is an object, so it can further be piped, e.g. to Out-GridView, Export-Csv, etc.

.PARAMETER InputObject
    Objects to process

    Mandatory
    Pipeline enabled
    accepts Arrays

.PARAMETER DifferenceOnly
    Switch to only output properties where the objects differ from each other

.EXAMPLE
    PS C:\> 'einstein','kierkegaard' | Get-ADUser | Out-Vertical
    
    Get's the basic AD data for users einstein ein kierkegaard and shows them next to each other in columns with the properties on the left:

    Properties          Object_1                    Object_2
    Name                EINSTEIN Albert             KIERKEGAARD Soeren
    Distinguishedname   CN=EINSTEIN Albert,OU=...   CN=KIERKEGAARD Soeren,OU=...
    SamAccountName      einstein                    kierkegaard
    ...                 ...                         ...
    
.INPUTS
    Any number or type of objects

.OUTPUTS
    A collection of objects, each object holding one property name and the associated values of all give input objects

.NOTES
    by Maximilian Otter, 201911

#>
function Out-Vertical {
    param (
        [Parameter(Mandatory,ValueFromPipeline,Position=0)]
        [PSCustomObject[]]$InputObject,
        [switch]$DifferenceOnly
    )

    begin {
        $Objects = [System.Collections.ArrayList]@()
    }
    
    process {
        # collect all objects, from pipeline or not
        foreach ($obj in $InputObject) {
            $null = $Objects.Add($obj)
        }   
    }

    end {
        
        # Collect properties of first object. Sort them, so we can use binary search for increased performance later
        $Properties = [System.Collections.ArrayList]($Objects[0].PSObject.Properties.Name | Sort-Object)

        # collect properties of all other objects if they have others and sort them in
        # the function can accept all sorts of objecst at once, so we have to get all properties from all objects,
        # even if it is e.g. an AD-User and a file (does not make sense, but nevertheless possible)
        for ($i = 1; $i -lt $Objects.count; $i++) {

            foreach ($prop in $Objects[$i].PSObject.Properties.Name) {
                $Index = $Properties.BinarySearch($prop)
                if ($Index -lt 0) {
                    $Properties.Insert(-1*($Index+1),$prop)
                }
            }

        }

        # Build an array of custom objects with one column holding the properties
        foreach ($prop in $Properties) {

            # exclude properties automatically created by the addresslist
            if ($prop -notin @('AddedProperties','ModifiedProperties','RemovedProperties','PropertyCount','PropertyNames')) {

                # first column will hold the properties of the objects. [Ordered] makes sure, it stays the first column.
                $hash = [Ordered]@{
                    Property = $prop
                }
            
                # add one column for each object
                $count = 1
                foreach ($obj in $Objects) {
                    $hash.Add("Object_$count",$obj.$prop)
                    $count++
                }
                
                # Did the user request to only output properties which differ from each other?
                if (-not($DifferenceOnly)) {

                    [PSCustomObject]$hash 

                } else {

                    $Output = $false
                    $Nulls = 0
                    $Fulls = 0

                    # check for not existing or $nul properties
                    # if we have $null and non-$null values, we already have a mismatch and may output the hash
                    foreach ($obj in $Objects) {
                        if ([string]::IsNullOrEmpty($obj.$prop)) { $Nulls++ } else { $Fulls++ }
                        if ($Nulls -and $Fulls) {
                            $Output = $true
                            break
                        }
                    }

                    # no output yet?
                    if (-not($Output)) {
                        # we can ignore $nulls -eq $Objects.count, because that means all are equal and we don't have to output them
                        # for all fulls...
                        if ($Fulls -eq $Objects.Count) {

                            # ...create -eq pairs of Object[0] comparing to all others
                            $filter_elements = for ($i = 1; $i -lt $Objects.Count -and -not($Output); $i++) {
                                '$Objects[0].$prop -eq $Objects[' + $i + ']'
                            }
                            # ... then join the pairs with -and and create a scriptblock of the filters to user with the following IF
                            $filter = [ScriptBlock]::Create(($filter_elements -join ' -and '))
                            # IF one of our -eq pairs does not match, we have a mismatch and may output the hash
                            if (-not(& $filter)) { $Output = $true }
                        }
                    }

                    if ($Output) {
                        [PSCustomObject]$hash
                    }
                }
            }
        }
    }
}