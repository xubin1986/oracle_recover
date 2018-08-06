#!/usr/bin/env python
#pip install pexect

import commands,time,os,sys,re,datetime,pexpect

def log(content):
    date = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print '%s  %s' % (date,content)

def localcmd(cmd,want=None,hate=None):
    wantret = 0
    hateret = 0
    date = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print '\n\nDate:  %s' % date
    print 'EXEC:  %s' % cmd
    status,out = commands.getstatusoutput('%s 2>&1' % cmd)
    if want:
        wantret = 0 if re.findall(want,out) else 1
    if hate:
        hateret = 1 if re.findall(hate,out) else 0
    ret = status + wantret + hateret
    print 'Status:  %s' % ret
    print 'OUTPUT:  %s' % out
    if ret > 0:
        sys.exit(1)
        
class Remote(object):
    def __init__(self,server,username,password):
        try:
            mself.con = pexpect.spawn('ssh %s@%s' % (username,password))
            self.con.expect('password:')
            self.con.sendline(password)
            self.con.expect(r'#|$',timeout=10)
        except Exception as e:
            log(str(e))
            sys.exit(1)
    def sshend(self):
        self.con.logout()
    def execcmd(self,cmd,want=None,hate=None,timeout=10):
        #import pdb;pdb.set_trace()
        wantret = 0
        hateret = 0
        date = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")        
        print '\n\nDate:  %s' % date
        print 'EXEC:  %s' % cmd        
        self.con.sendline(cmd)
        try:
            self.con.expect('#',timeout=timeout)
        except:
            print 'Status:  %s' % 127
            print 'OUTPUT:  Timeout when exec [%s]' % cmd
            sys.exit(1)
        out = self.con.before
        self.con.sendline('echo $?')
        self.con.prompt()
        status = self.con.before.split('\n')[-2]
        if want:
            wantret = 0 if re.findall(want,out) else 1
        if hate:
            hateret = 1 if re.findall(hate,out) else 0
        ret = int(status) + wantret + hateret
        print 'Status:  %s' % ret
        print 'OUTPUT:  %s' % out
        if ret > 0:
            self.sshend()
            sys.exit(1)        
    def execsql(self,sql,want=None,hate=None,timeout=10):
        wantret = 0
        hateret = 0   
        date = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        print '\n\nDate:  %s' % date
        print 'EXEC(sqlplus):  %s' % cmd        
        self.con.sendline(cmd)
        try:
            self.con.expect('SQL>',timeout=timeout)
        except:
            print 'Status:  %s' % 127
            print 'OUTPUT:  Timeout when exec [%s]' % cmd
            self.sqlend()
            sys.exit(1)            
        out = self.con.before
        if want:
            wantret = 0 if re.findall(want,out) else 1
        if hate:
            hateret = 1 if re.findall(hate,out) else 0
        ret = wantret + hateret
        print 'Status:  %s' % ret
        print 'OUTPUT:  %s' % out
        if ret > 0:
            self.sqlend()
            sys.exit(1) 
    def sqlbegin():
        self.con.sendline('su - oracle;sqlplus /as sysdba')
        try:
            self.con.expect('SQL>',timeout=5)
        except:
            log('Failed to start sqlplus')
            sys.exit(1)
    def sqlend():
        self.con.sendline('exit')
        try:
            self.con.prompt()
        except:
            log('Failed to exit SQL')
 

#main code
host = '114.115.178.125'
user = 'ops'
password = '1qaz2wsx' 
localcmd('hostname')
remote = Remote(server=host,username=user,password=password)
remote.execcmd('sleep 5')
remote.sshend()
sys.exit(0)        
