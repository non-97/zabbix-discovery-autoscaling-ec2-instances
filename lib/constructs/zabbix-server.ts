import * as cdk from "aws-cdk-lib";
import { Construct } from "constructs";
import * as fs from "fs";
import * as path from "path";

export interface ZabbixServerProps {
  vpc: cdk.aws_ec2.IVpc;
}

export class ZabbixServer extends Construct {
  readonly instance: cdk.aws_ec2.IInstance;

  constructor(scope: Construct, id: string, props: ZabbixServerProps) {
    super(scope, id);

    // User data
    const userDataScript = fs.readFileSync(
      path.join(__dirname, "../ec2/user-data-zabbix-server.sh"),
      "utf8"
    );
    const userData = cdk.aws_ec2.UserData.forLinux();
    userData.addCommands(userDataScript);

    // EC2 Instance
    this.instance = new cdk.aws_ec2.Instance(this, "Default", {
      machineImage: cdk.aws_ec2.MachineImage.lookup({
        name: "RHEL-9.2.0_HVM-20230905-x86_64-38-Hourly2-GP2",
        owners: ["309956199498"],
      }),
      instanceType: new cdk.aws_ec2.InstanceType("t3.small"),
      blockDevices: [
        {
          deviceName: "/dev/sda1",
          volume: cdk.aws_ec2.BlockDeviceVolume.ebs(10, {
            volumeType: cdk.aws_ec2.EbsDeviceVolumeType.GP3,
            encrypted: true,
          }),
        },
      ],
      vpc: props.vpc,
      vpcSubnets: props.vpc.selectSubnets({
        subnetGroupName: "Public",
      }),
      propagateTagsToVolumeOnCreation: true,
      ssmSessionPermissions: true,
      userData,
      requireImdsv2: false,
    });
  }
}
