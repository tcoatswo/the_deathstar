#!/usr/bin/env ruby		 
#	 			 		
#	DeathStar   
#		Version 1.0         
#				 
#	Author: Tyler Coatsworth 
#		Date July, 2016	 
#				 
#/////////////////////////////////  
require 'find'
require 'expect'
require 'fileutils'
require 'pathname'
require 'pty'
require 'digest/md5'
require 'io/console'

$deathstarNumber = 1
ipListLocation = "/home/ubuntu/IPlist.txt"

# Colors! << Usage: puts color('text') >>
	def colorize(number, text) 
		"\e[#{number}m#{text}\e[0m" 
	end 

	def red(text); colorize(31, text); end
	def green(text); colorize(32, text); end
	def amber(text); colorize(33, text); end
	def blue(text); colorize(34, text); end
	def purple(text); colorize(35, text); end
	def teal(text); colorize(36, text); end
#/////////////////////////////////////////////

def parse_list(ipListLocation)
		line_count = IO.readlines(ipListLocation).size  
		remainder = line_count % 10
		box_num = line_count / 10
		if remainder > 0
			$deathstarNumber = box_num + 1
		end

end

def bruccy(fileloc, startline)

    endline = IO.readlines(fileloc).size
    count = 0
    c=count.to_i
	count=count+1
    aa=[]
	startline = startline - 1
    while count <= 10 do
        aa[c..endline] = IO.readlines(fileloc)
		system("touch /home/ubuntu/bruccy_ip.txt")
		system("printf \"#{aa[startline]}\" >> /home/ubuntu/bruccy_ip.txt")
       startline += 1
        count += 1
   end
	system("cat /home/ubuntu/bruccy_ip.txt") #probably leave me in here for debug porpoises.
	puts ("==============================================")
end


def copy_list_into_dockers(ipListLocation, deathstarNumber)
		v = 1
	for i in 1..deathstarNumber do
		if i > 1
		v += 10
		end
		bruccy(ipListLocation, v)
		
		death_count = "deathstar" + i.to_s
			system("docker cp /home/ubuntu/bruccy_ip.txt #{death_count}:/IPlist.txt")	
			system("rm /home/ubuntu/bruccy_ip.txt")
	end
	
end

def create_start_dockers(deathstarNumber)
	#puts ("CSD imported number of death stars: #{deathstarNumber}")
	k = 1
	donewithstars = deathstarNumber + 1
	
	while k < donewithstars do
		system("docker run --name deathstar#{k} -d -it ubuntu:v10")
		k+=1
		#puts ("k is: #{k}")
	end
end

def exec_laser_startup(deathstarNumber)
	#puts ("ELS imported number of death stars: #{deathstarNumber}")
	$i = 1
	$done = deathstarNumber + 1
		
	while $i < $done do
		system("docker exec -d deathstar#{$i} python start.py")
		puts green("FIRING: deathstar#{$i}")
		$i +=1
	end
end

def clean_up_the_evidence()
	system("docker stop $(docker ps -a -q)")
	system("docker rm $(docker ps -a -q)")
end

def recursive_timed_copy(deathstarNumber)
	puts amber("STATUS: Initiating recursive copy, once per minute.")
	system("mkdir /home/ubuntu/SCAN-RESULTS/")
	sleep(60)
	$c = 1
	$maxtime = deathstarNumber + 1
	$timer = 1
	$maxtime = 30
	
	while $timer < $maxtime # runs this loop for maxtime * 60 (seconds), to recursively copy files on a period of 1 minute.
		while $c < $done do
			system("docker cp deathstar#{$c}:/home/ /home/ubuntu/SCAN-RESULTS/deathstar#{$c}-results")
			puts green("Copying Files from: deathstar#{$c}")
			$c +=1
		end
		$c = 1
		puts amber("... Results from #{$timer} minute(s)")
		$timer += 1
		sleep(60) # waits for 1 minute
		system("rm -R /home/ubuntu/SCAN-RESULTS/")
		system("mkdir /home/ubuntu/SCAN-RESULTS/")
	end
end

puts teal('STATUS: Deleting old deathstars...')
clean_up_the_evidence()
puts teal('STATUS: DeathStar Assembly In Progress...')
sleep(2)
parse_list(ipListLocation)
puts amber("Preparing to create #{$deathstarNumber} deathstars")
create_start_dockers($deathstarNumber)
puts amber('---[LOCKING COORDINATES]---')
sleep(3)
system("cat /home/ubuntu/IPlist.txt")
system("echo  ")
sleep(2)
puts amber('STATUS: Charging lazer...')
sleep(2)
copy_list_into_dockers(ipListLocation, $deathstarNumber)
sleep(1)
puts green('STATUS: Charge Complete.')
sleep(2)
puts teal('Countdown to the destruction of Alderaan:')
sleep(2)
puts red('3...')
sleep(1)
puts amber('2...')
sleep(1)
puts green('1...')
sleep(1)
puts red('---[FIRING DEATH STAR]---')
sleep(3)
exec_laser_startup($deathstarNumber)
puts red("ALL YOUR BASE ARE BELONG TO US.")
puts blue('------------------------')
sleep(2)
puts green('Target is a confirmed hit.')
sleep(2)
puts amber('Alderaan has been destroyed.')
sleep(2)
puts red('---[SHUTTING DOWN DEATHSTAR]---')
sleep(2)
recursive_timed_copy($deathstarNumber)
clean_up_the_evidence()
