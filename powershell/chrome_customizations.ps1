#Copyright (c) 2015 Serguei Kouzmine
#
#Permission is hereby granted, free of charge, to any person obtaining a copy
#of this software and associated documentation files (the "Software"), to deal
#in the Software without restriction, including without limitation the rights
#to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
#copies of the Software, and to permit persons to whom the Software is
#furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in
#all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
#THE SOFTWARE.

param(
  [string]$browser
)


function read_registry {
  param([string]$registry_path,
    [string]$package_name,
    [string]$subfolder

  )

  $install_location_result = $null
  pushd HKLM:

  cd $registry_path
  $apps = Get-ChildItem -Path .

  $apps | ForEach-Object {

    $registry_key = $_


    pushd $registry_key.Path
    $values = $registry_key.GetValueNames()

    if (-not ($values.GetType().BaseType.Name -match 'Array')) {
      throw 'Unexpected result type'
    }


    $values | Where-Object { $_ -match '^DisplayName$' } | ForEach-Object {

      try {
        $displayname_result = $registry_key.GetValue($_).ToString()

      } catch [exception]{
        Write-Debug $_
      }


      if ($displayname_result -ne $null -and $displayname_result -match "\b${package_name}\b") {
        $values2 = $registry_key.GetValueNames()
        $install_location_result = $null
        $values2 | Where-Object { $_ -match '\bInstallLocation\b' } | ForEach-Object {
          $install_location_result = $registry_key.GetValue($_).ToString()
          Write-Host -ForegroundColor 'yellow' (($displayname_result,$registry_key.Name,$install_location_result) -join "`r`n")
        }
      }
    }
    popd
  }
  popd
  return ('{0}{1}' -f $install_location_result,$subfolder)
}

function cleanup
{
  param(
    [System.Management.Automation.PSReference]$selenium_ref
  )
  try {
    $selenium_ref.Value.Quit()
  } catch [exception]{
    # Ignore errors if unable to close the browser
    Write-Output (($_.Exception.Message) -split "`n")[0]

  }
}

# http://stackoverflow.com/questions/8343767/how-to-get-the-current-directory-of-the-cmdlet-being-executed
function Get-ScriptDirectory
{
  $Invocation = (Get-Variable MyInvocation -Scope 1).Value
  if ($Invocation.PSScriptRoot) {
    $Invocation.PSScriptRoot
  }
  elseif ($Invocation.MyCommand.Path) {
    Split-Path $Invocation.MyCommand.Path
  } else {
    $Invocation.InvocationName.Substring(0,$Invocation.InvocationName.LastIndexOf(""))
  }
}

function create_table {
  param(
    [string]$database = "$(Get-ScriptDirectory)\timings.db",
    # http://www.sqlite.org/datatype3.html
    [string]$create_table_query = @"
   CREATE TABLE IF NOT EXISTS [timings]
      (  ID       INTEGER PRIMARY KEY   AUTOINCREMENT,
         URL      CHAR(2048),
         CAPTION   CHAR(256),
         LOADTIME    DECIMAL 
      );

"@
  )
  [int]$version = 3
  $connection = New-Object System.Data.SQLite.SQLiteConnection ('Data Source={0};Version={1};' -f $database,$version)
  $connection.Open()
  Write-Output $create_table_query
  [System.Data.SQLite.SQLiteCommand]$sql_command = New-Object System.Data.SQLite.SQLiteCommand ($create_table_query,$connection)
  try {
    $sql_command.ExecuteNonQuery()
  } catch [exception]{
  }
  $connection.Close()


}

function insert_database3 {
  param(
    [string]$database = "$(Get-ScriptDirectory)\timings.db",
    [string]$query = @"
INSERT INTO [timings] (CAPTION, URL, LOADTIME )  VALUES(?, ?, ?)
"@,
    [psobject]$data
  )


  [int]$version = 3
  $connection_string = ('Data Source={0};Version={1};' -f $database,$version)
  $connection = New-Object System.Data.SQLite.SQLiteConnection ($connection_string)
  $connection.Open()
  Write-Output $query
  $command = $connection.CreateCommand()
  $command.CommandText = $query

  $caption = New-Object System.Data.SQLite.SQLiteParameter
  $url = New-Object System.Data.SQLite.SQLiteParameter
  $load_time = New-Object System.Data.SQLite.SQLiteParameter


  $command.Parameters.Add($caption)
  $command.Parameters.Add($url)
  $command.Parameters.Add($load_time)

  $caption.Value = $data.caption
  $url.Value = $data.url
  $load_time.Value = $data.load_time
  $rows_inserted = $command.ExecuteNonQuery()
  $command.Dispose()
}



$shared_assemblies = @(
  'WebDriver.dll',
  'WebDriver.Support.dll',
  'nunit.core.dll',
  'nunit.framework.dll'
)

$shared_assemblies_path = 'c:\developer\sergueik\csharp\SharedAssemblies'

if (($env:SHARED_ASSEMBLIES_PATH -ne $null) -and ($env:SHARED_ASSEMBLIES_PATH -ne '')) {
  $shared_assemblies_path = $env:SHARED_ASSEMBLIES_PATH
}
pushd $shared_assemblies_path
$shared_assemblies | ForEach-Object { Unblock-File -Path $_; Add-Type -Path $_ }
popd

$extra_assemblies_path = read_registry -subfolder 'bin' -registry_path '/SOFTWARE/Microsoft/Windows/CurrentVersion/Uninstall/' -package_name 'System.Data.SQLite'
$extra_assemblies = @(
  'System.Data.SQLite.dll'
)

pushd $extra_assemblies_path
$extra_assemblies | ForEach-Object { Unblock-File -Path $_; Add-Type -Path $_ }
popd


$headless = $false

$verificationErrors = New-Object System.Text.StringBuilder
$base_url = 'http://www.carnival.com/'

if ($browser -ne $null -and $browser -ne '') {
  try {
    $connection = (New-Object Net.Sockets.TcpClient)
    $connection.Connect("127.0.0.1",4444)
    $connection.Close()
  } catch {
    Start-Process -FilePath "C:\Windows\System32\cmd.exe" -ArgumentList "start /min cmd.exe /c c:\java\selenium\hub.cmd"
    Start-Process -FilePath "C:\Windows\System32\cmd.exe" -ArgumentList "start /min cmd.exe /c c:\java\selenium\node.cmd"
    Start-Sleep -Seconds 10
  }
  Write-Host "Running on ${browser}"
  $selenium = $null
  if ($browser -match 'firefox') {
    $capability = [OpenQA.Selenium.Remote.DesiredCapabilities]::Firefox()

  }
  elseif ($browser -match 'chrome') {
    $capability = [OpenQA.Selenium.Remote.DesiredCapabilities]::Chrome()
    # override

    # Oveview of extensions 
    # https://sites.google.com/a/chromium.org/chromedriver/capabilities

    # Profile creation
    # https://support.google.com/chrome/answer/142059?hl=en
    # http://www.labnol.org/software/create-family-profiles-in-google-chrome/4394/
    # using Profile 
    # http://superuser.com/questions/377186/how-do-i-start-chrome-using-a-specified-user-profile/377195#377195


    # origin:
    # http://stackoverflow.com/questions/20401264/how-to-access-network-panel-on-google-chrome-developer-toools-with-selenium

    [OpenQA.Selenium.Chrome.ChromeOptions]$options = New-Object OpenQA.Selenium.Chrome.ChromeOptions

    $options.addArguments('start-maximized')
    # no-op option - re-enforcing the default setting
    $options.addArguments(('user-data-dir={0}' -f ("${env:LOCALAPPDATA}\Google\Chrome\User Data" -replace '\\','/')))
    # if you like to specify another profile parent directory:
    # $options.addArguments('user-data-dir=c:/TEMP'); 

    $options.addArguments('--profile-directory=Default')

    [OpenQA.Selenium.Remote.DesiredCapabilities]$capabilities = [OpenQA.Selenium.Remote.DesiredCapabilities]::Chrome()
    $capabilities.setCapability([OpenQA.Selenium.Chrome.ChromeOptions]::Capability,$options)

    $selenium = New-Object OpenQA.Selenium.Chrome.ChromeDriver ($options)




  }
  elseif ($browser -match 'ie') {
    $capability = [OpenQA.Selenium.Remote.DesiredCapabilities]::InternetExplorer()
    if ($version -ne $null -and $version -ne 0) {
      $capability.setCapability("version",$version.ToString());
    }

  }
  elseif ($browser -match 'safari') {
    $capability = [OpenQA.Selenium.Remote.DesiredCapabilities]::Safari()
  }
  else {
    throw "unknown browser choice:${browser}"
  }
  if ($selenium -eq $null) {
    $uri = [System.Uri]("http://127.0.0.1:4444/wd/hub")
    $selenium = New-Object OpenQA.Selenium.Remote.RemoteWebDriver ($uri,$capability)
  }
} else {

  Write-Host 'Running on phantomjs'
  $headless = $true
  $phantomjs_executable_folder = "C:\tools\phantomjs-2.0.0\bin"
  #  $phantomjs_executable_folder = "C:\tools\phantomjs-1.9.7"
  $selenium = New-Object OpenQA.Selenium.PhantomJS.PhantomJSDriver ($phantomjs_executable_folder)
  $selenium.Capabilities.setCapability("ssl-protocol","any")
  $selenium.Capabilities.setCapability("ignore-ssl-errors",$true)
  $selenium.Capabilities.setCapability("takesScreenshot",$true)
  $selenium.Capabilities.setCapability("userAgent","Mozilla/5.0 (Windows NT 6.1) AppleWebKit/534.34 (KHTML, like Gecko) PhantomJS/1.9.7 Safari/534.34")
  $options = $null
  $options = New-Object OpenQA.Selenium.PhantomJS.PhantomJSOptions
  $options.AddAdditionalCapability("phantomjs.executable.path",$phantomjs_executable_folder)
}


Add-Type @"

using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using OpenQA.Selenium;

namespace WaitForExtensions
{
    public static class DocumentReadyState
    {
        static int cnt = 0;
        static string expected_state = "complete";
        public static void Wait(/* this // no longer is an extension method  */ IWebDriver driver)
        {
            var wait = new OpenQA.Selenium.Support.UI.WebDriverWait(driver, TimeSpan.FromSeconds(30.00));
            wait.PollingInterval = TimeSpan.FromSeconds(0.50);
            wait.Until(dummy => ((IJavaScriptExecutor)driver).ExecuteScript("return document.readyState").Equals(expected_state));
        }

        public static void Wait2(/* this // no longer is an extension method  */ IWebDriver driver)
        {
            var wait = new OpenQA.Selenium.Support.UI.WebDriverWait(driver, TimeSpan.FromSeconds(30.00));
            wait.PollingInterval = TimeSpan.FromSeconds(0.50);
            wait.Until(dummy =>
            {
                string result = ((IJavaScriptExecutor)driver).ExecuteScript("return document.readyState").ToString();
                Console.Error.WriteLine(String.Format("result = {0}", result));
                Console.WriteLine(String.Format("cnt = {0}", cnt));
                cnt++;
                return ((result.Equals(expected_state) || cnt > 5));
            });
        }
    }

}
"@ -ReferencedAssemblies 'System.dll','System.Data.dll','System.Data.Linq.dll',"${shared_assemblies_path}\WebDriver.dll","${shared_assemblies_path}\WebDriver.Support.dll"

# Actual action .
$script_directory = Get-ScriptDirectory

create_table -database "${script_directory}\timings.db"

$selenium.Navigate().GoToUrl($base_url)
[WaitForExtensions.DocumentReadyState]::Wait2($selenium)
$script = @"
var ua = window.navigator.userAgent;


if (ua.match(/PhantomJS/)) { 
return 'Cannot measure on '+ ua;
}
else{
var performance = 
      window.performance || 
      window.mozPerformance || 
      window.msPerformance || 
      window.webkitPerformance || {}; 
// var timings = performance.timing || {};
// return timings;
// NOTE:  performance.timing will not return anything with Chrome
// timing is returned by FF
// timing is returned by Phantom
var network = performance.getEntries() || {}; 
 return network;
}


"@

# executeScript works fine with Chrome or Firefox 31, ie 10, but not IE 11.
# Exception calling "ExecuteScript" with "1" argument(s): "Unable to get browser
# https://code.google.com/p/selenium/issues/detail?id=6511  
# 
# https://code.google.com/p/selenium/source/browse/java/client/src/org/openqa/selenium/remote/HttpCommandExecutor.java?r=3f4622ced689d2670851b74dac0c556bcae2d0fe

$savedata = $true

if ($headless) {
  # for PhantomJS more work is needed
  # https://github.com/detro/ghostdriver/blob/master/binding/java/src/main/java/org/openqa/selenium/phantomjs/PhantomJSDriver.java
  $result = ([OpenQA.Selenium.PhantomJS.PhantomJSDriver]$selenium).ExecutePhantomJS($script,[System.Object[]]@())
  $result | Format-List
  return
} else {

  $result = ([OpenQA.Selenium.IJavaScriptExecutor]$selenium).executeScript($script)
  # $result | get-member 

  $result | ForEach-Object {
    $element_result = $_
    # $element_result | format-list
    Write-Output $element_result.Name
    Write-Output $element_result.duration
    $o = New-Object PSObject
    $caption = 'test'
    $o | Add-Member Noteproperty 'url' $element_result.Name
    $o | Add-Member Noteproperty 'caption' $caption
    $o | Add-Member Noteproperty 'load_time' $element_result.duration
    $o | Format-List

    if ($savedata) {
      insert_database3 -data $o -database "$script_directory\timings.db"
    }
    $o = $null

  }
}
# How to build a waterfall gantt chart .
# http://blog.trasatti.it/2012/11/measuring-site-performance-with-javascript-on-mobile.html
# http://stackoverflow.com/questions/240333/how-do-you-measure-page-load-speed
# http://checkvincode.ru/p.php?t=Measure+Web+Page+Load+Time

# Cleanup

cleanup ([ref]$selenium)
