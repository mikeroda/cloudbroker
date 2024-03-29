INSERT INTO `vcl`.`module`
(`id` ,
`name` ,
`prettyname` ,
`description` ,
`perlpackage` )
VALUES
('26', 'terremark', 'Terremark Provisioning Module', 
 'Provisioning Module for Terremark vCloud Express API v0.8a-ext1.6', 'VCL::Module::Provisioning::tmrk');

INSERT INTO `vcl`.`module`
(`id` ,
`name` ,
`prettyname` ,
`description` ,
`perlpackage` )
VALUES
('27', 'os_linux_tmrk', 'Linux OS Module for Terremark', 
 'Linux OS Module for Terremark vCloud Express virtual machines', 'VCL::Module::OS::Linux::Linux_tmrk');

INSERT INTO `vcl`.`provisioning`
(`id` ,
`name` ,
`prettyname` ,
`moduleid` )
VALUES
('9', 'terremark', 'Terremark Provisioning', '26');

INSERT INTO `vcl`.`OS`
(`id` ,
`name` ,
`prettyname` ,
`type` ,
`installtype` ,
`sourcepath` ,
`moduleid` )
VALUES
('39', 'rhel5tmrk', 'Red Hat Enterprise Linux 5 (Terremark)', 'linux', 'none', NULL, '27');

INSERT INTO `vcl`.`provisioningOSinstalltype`
(`provisioningid` ,
`OSinstalltypeid` )
VALUES 
('9', '3');

INSERT INTO `vcl`.`image`
(`id` ,
`name` ,
`prettyname` ,
`ownerid` ,
`platformid` ,
`OSid` ,
`imagemetaid` ,
`minram` ,
`minprocnumber` ,
`minprocspeed` ,
`minnetwork` ,
`maxconcurrent` ,
`reloadtime` ,
`deleted` ,
`test` ,
`lastupdate` ,
`forcheckout` ,
`maxinitialtime` ,
`project` ,
`size` ,
`architecture` ,
`description` ,
`usage` ,
`basedoffrevisionid`)
VALUES
('8' , 'tmrk-centos5-32bit', 'CentOS 5 (32-bit)', '1', '1', '39', NULL,
'512', '1', '1000', '100', NULL , '5', '0', '0', NOW(), '1', '0', 'vcl', '1500',
'x86', NULL , NULL , '0'
);

INSERT INTO `vcl`.`image`
(`id` ,
`name` ,
`prettyname` ,
`ownerid` ,
`platformid` ,
`OSid` ,
`imagemetaid` ,
`minram` ,
`minprocnumber` ,
`minprocspeed` ,
`minnetwork` ,
`maxconcurrent` ,
`reloadtime` ,
`deleted` ,
`test` ,
`lastupdate` ,
`forcheckout` ,
`maxinitialtime` ,
`project` ,
`size` ,
`architecture` ,
`description` ,
`usage` ,
`basedoffrevisionid`)
VALUES
('9' , 'tmrk-centos5-64bit', 'CentOS 5 (64-bit)', '1', '1', '39', NULL,
'1024', '1', '2000', '100', NULL , '5', '0', '0', NOW(), '1', '0', 'vcl', '1500',
'x86', NULL , NULL , '0'
);

INSERT INTO `vcl`.`image`
(`id` ,
`name` ,
`prettyname` ,
`ownerid` ,
`platformid` ,
`OSid` ,
`imagemetaid` ,
`minram` ,
`minprocnumber` ,
`minprocspeed` ,
`minnetwork` ,
`maxconcurrent` ,
`reloadtime` ,
`deleted` ,
`test` ,
`lastupdate` ,
`forcheckout` ,
`maxinitialtime` ,
`project` ,
`size` ,
`architecture` ,
`description` ,
`usage` ,
`basedoffrevisionid`)
VALUES
('10' , 'tmrk-rhel5-32bit', 'RHEL 5 (32-bit)', '1', '1', '39', NULL,
'512', '1', '1000', '100', NULL , '5', '0', '0', NOW(), '1', '0', 'vcl', '1500',
'x86', NULL , NULL , '0'
);

INSERT INTO `vcl`.`image`
(`id` ,
`name` ,
`prettyname` ,
`ownerid` ,
`platformid` ,
`OSid` ,
`imagemetaid` ,
`minram` ,
`minprocnumber` ,
`minprocspeed` ,
`minnetwork` ,
`maxconcurrent` ,
`reloadtime` ,
`deleted` ,
`test` ,
`lastupdate` ,
`forcheckout` ,
`maxinitialtime` ,
`project` ,
`size` ,
`architecture` ,
`description` ,
`usage` ,
`basedoffrevisionid`)
VALUES
('11' , 'tmrk-rhel5-64bit', 'RHEL 5 (64-bit)', '1', '1', '39', NULL,
'1024', '1', '2000', '100', NULL , '5', '0', '0', NOW(), '1', '0', 'vcl', '1500',
'x86', NULL , NULL , '0'
);

INSERT INTO `vcl`.`imagerevision` (
`id` ,
`imageid` ,
`revision` ,
`userid` ,
`datecreated` ,
`deleted` ,
`datedeleted` ,
`production` ,
`comments` ,
`imagename`
)
VALUES (
NULL , '8', '1', '1', NOW(), '0', NULL , '1', NULL , 'tmrk-centos5-32bit'
);

INSERT INTO `vcl`.`imagerevision` (
`id` ,
`imageid` ,
`revision` ,
`userid` ,
`datecreated` ,
`deleted` ,
`datedeleted` ,
`production` ,
`comments` ,
`imagename`
)
VALUES (
NULL , '9', '1', '1', NOW(), '0', NULL , '1', NULL , 'tmrk-centos5-64bit'
);

INSERT INTO `vcl`.`imagerevision` (
`id` ,
`imageid` ,
`revision` ,
`userid` ,
`datecreated` ,
`deleted` ,
`datedeleted` ,
`production` ,
`comments` ,
`imagename`
)
VALUES (
NULL , '10', '1', '1', NOW(), '0', NULL , '1', NULL , 'tmrk-rhel5-32bit'
);

INSERT INTO `vcl`.`imagerevision` (
`id` ,
`imageid` ,
`revision` ,
`userid` ,
`datecreated` ,
`deleted` ,
`datedeleted` ,
`production` ,
`comments` ,
`imagename`
)
VALUES (
NULL , '11', '1', '1', NOW(), '0', NULL , '1', NULL , 'tmrk-rhel5-64bit'
);

INSERT INTO `vcl`.`resource` (
`id` ,
`resourcetypeid` ,
`subid`
)
VALUES (
NULL , '13', '8'
);

INSERT INTO `vcl`.`resource` (
`id` ,
`resourcetypeid` ,
`subid`
)
VALUES (
NULL , '13', '9'
);

INSERT INTO `vcl`.`resource` (
`id` ,
`resourcetypeid` ,
`subid`
)
VALUES (
NULL , '13', '10'
);

INSERT INTO `vcl`.`resource` (
`id` ,
`resourcetypeid` ,
`subid`
)
VALUES (
NULL , '13', '11'
);
