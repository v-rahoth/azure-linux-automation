﻿<#-------------Create Deployment Start------------------#>
Import-Module .\TestLibs\RDFELibs.psm1 -Force

$result = ""
$testResult = ""
$resultArr = @()

$isDeployed = DeployVMS -setupType $currentTestData.setupType -Distro $Distro -xmlConfig $xmlConfig
if ($isDeployed)
{
	$hs1Name = $isDeployed
	$testServiceData = Get-AzureService -ServiceName $hs1Name

#Get VMs deployed in the service..
	$testVMsinService = $testServiceData | Get-AzureVM

	$hs1vm1 = $testVMsinService[0]
	$hs1vm1Endpoints = $hs1vm1 | Get-AzureEndpoint

	$hs1VIP = $hs1vm1Endpoints[0].Vip
	$hs1ServiceUrl = $hs1vm1.DNSName
	$hs1ServiceUrl = $hs1ServiceUrl.Replace("http://","")
	$hs1ServiceUrl = $hs1ServiceUrl.Replace("/","")
	$hs1vm1IP = $hs1vm1.IpAddress
	$hs1vm1Hostname = $hs1vm1.InstanceName

	$hs1vm2 = $testVMsinService[1]
	$hs1vm2Endpoints = $hs1vm2 | Get-AzureEndpoint
	$hs1vm2IP = $hs1vm2.IpAddress
	$hs1vm2Hostname = $hs1vm2.InstanceName


	$hs1vm1tcpport = GetPort -Endpoints $hs1vm1Endpoints -usage tcp
	$hs1vm2tcpport = GetPort -Endpoints $hs1vm2Endpoints -usage tcp
	$hs1vm1sshport = GetPort -Endpoints $hs1vm1Endpoints -usage ssh
	$hs1vm2sshport = GetPort -Endpoints $hs1vm2Endpoints -usage ssh
	$hs1vm1ProbePort = GetProbePort -Endpoints $hs1vm1Endpoints -usage TCPtest
	$hs1vm2ProbePort = GetProbePort -Endpoints $hs1vm2Endpoints -usage TCPtest

	$dtapServerTcpport = "750"
	$dtapServerUdpport = "990"
	$dtapServerSshport = "22"

#$dtapServerIp="131.107.220.167"
	$wait=30

	$cmd1="./start-server.py -p $hs1vm1tcpport && mv Runtime.log start-server.py.log -f"
	$cmd2="./start-server.py -p $hs1vm2tcpport && mv Runtime.log start-server.py.log -f"

	$server1 = CreateIperfNode -nodeIp $hs1VIP -nodeSshPort $hs1vm1sshport -nodeTcpPort $hs1vm1tcpport -nodeIperfCmd $cmd1 -user $user -password $password -files $currentTestData.files -logDir $LogDir -nodeDip $hs1vm1.IpAddress
	$server2 = CreateIperfNode -nodeIp $hs1VIP -nodeSshPort $hs1vm2sshport -nodeTcpPort $hs1vm2tcpport -nodeIperfCmd $cmd2 -user $user -password $password -files $currentTestData.files -logDir $LogDir -nodeDip $hs1vm2.IpAddress
	$client = CreateIperfNode -nodeIp $dtapServerIp -nodeSshPort $dtapServerSshport -nodeTcpPort $dtapServerTcpport -nodeIperfCmd $cmd3 -user $user -password $password -files $currentTestData.files -logDir $LogDir
	$resultArr = @()
	$result = "", ""
	$Value = 2

	foreach ($mode in $currentTestData.TestMode.Split(",")) 
	{
		mkdir $LogDir\$mode -ErrorAction SilentlyContinue | out-null

		try
		{
			LogMsg "Starting test for $Value parallel connections in $mode mode.."
			LogMsg "Trying to access non defined TCP port ... $hs1vm1tcpport."
			if(($mode -eq "IP") -or ($mode -eq "VIP") -or ($mode -eq "DIP"))
			{#.........................................................................Client command will decided according to TestMode....
				$cmd3="./start-client.py -c $hs1VIP -p $hs1vm1tcpport -t20 -P$Value" 
			}
			if(($mode -eq "URL") -or ($mode -eq "Hostname"))
			{
				$cmd3="./start-client.py -c $hs1ServiceUrl -p $hs1vm1tcpport -t20 -P$Value"
			}
			$client.cmd = $cmd3
			mkdir $LogDir\$mode\Server1 -ErrorAction SilentlyContinue | out-null
			mkdir $LogDir\$mode\Server2 -ErrorAction SilentlyContinue | out-null
			$server1.logDir = "$LogDir\$mode\Server1"
			$server2.logDir = "$LogDir\$mode\Server2"
			$client.logDir = $LogDir + "\$mode"
			$client.cmd = $cmd3

			RemoteCopy -uploadTo $server1.ip -port $server1.sshPort -files $server1.files -username $server1.user -password $server1.password -upload
			RemoteCopy -uploadTo $server2.Ip -port $server2.sshPort -files $server2.files -username $server2.user -password $server2.password -upload
			RemoteCopy -uploadTo $client.Ip -port $client.sshPort -files $client.files -username $client.user -password $client.password -upload

			$suppressedOut = RunLinuxCmd -username $server2.user -password $server2.password -ip $server2.ip -port $server2.sshPort -command "chmod +x *.py" -runAsSudo
			$suppressedOut = RunLinuxCmd -username $server1.user -password $server1.password -ip $server1.ip -port $server1.sshPort -command "chmod +x *.py" -runAsSudo
			$suppressedOut = RunLinuxCmd -username $client.user -password $client.password -ip $client.ip -port $client.sshPort -command "chmod +x *.py" -runAsSudo

			$suppressedOut = RunLinuxCmd -username $server1.user -password $server1.password -ip $server1.ip -port $server1.sshport -command "echo Test Started > iperf-server.txt" -runAsSudo
			$suppressedOut = RunLinuxCmd -username $server2.user -password $server2.password -ip $server2.ip -port $server2.sshPort -command "echo Test Started > iperf-server.txt" -runAsSudo

			StartIperfServer $server1
			StartIperfServer $server2

			$isServer1Started = IsIperfServerStarted $server1
			$isServer2Started = IsIperfServerStarted $server2
			Sleep($wait)
			if(($isServer1Started -eq $true) -and ($isServer2Started -eq $true)) 
			{
				LogMsg "Iperf Server1 and Server2 started successfully. Listening TCP port $($client.tcpPort) for probe messages..."
#>>>On confirmation, of server starting, wait 30 seconds for probe messages
				WaitFor -seconds 30
				$server1State = IsIperfServerRunning $server1
				$server2State = IsIperfServerRunning $server2
				if(($server1State -eq $true) -or ($server2State -eq $true)) 
				{
					LogErr ".. whoa, whoa, whoa.!!. Server got some connections messages. THATS NOT EXPECTED."
					LogMsg "Please check out the logs.."
					$testResult = "FAIL"
				} 
				else 
				{
					LogMsg "Test Finished..!"
					$testResult = "PASS"
				}

			} 
			else	
			{
				LogErr "Unable to start iperf-server. Aborting test."
				RemoteCopy -download -downloadFrom $server1.ip -files "/home/test/iperf-server.txt" -downloadTo $server1.LogDir -port $server1.sshPort -username $server1.user -password $server1.password
				RemoteCopy -download -downloadFrom $server2.ip -files "/home/test/iperf-server.txt" -downloadTo $server2.LogDir -port $server2.sshPort -username $server2.user -password $server2.password
				$testResult = "Aborted"
			}

			LogMsg "Test Finished, result is $testResult"
		}
		catch
		{
			$ErrorMessage =  $_.Exception.Message
			LogErr "EXCEPTION : $ErrorMessage"   
		}
		Finally
		{
			$metaData = " tcpport used : $hs1vm1tcpport " 
			if (!$testResult)
			{
				$testResult = "Aborted"
			}
			$resultArr += $testResult
			$resultSummary +=  CreateResultSummary -testResult $testResult -metaData $metaData -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName# if you want to publish all result then give here all test status possibilites. if you want just failed results, then give here just "FAIL". You can use any combination of PASS FAIL ABORTED and corresponding test results will be published!
		}   

	}

}
else
{
	$testResult = "Aborted"
	$resultArr += $testResult
}

$result = GetFinalResultHeader -resultarr $resultArr

#Clean up the setup
DoTestCleanUp -result $result -testName $currentTestData.testName -deployedServices $isDeployed

#Return the result and summery to the test suite script..
return $result,$resultSummary
