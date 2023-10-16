import * as cdk from "aws-cdk-lib";
import { Construct } from "constructs";
import { Vpc } from "./constructs/vpc";
import { Route53 } from "./constructs/route53";
import { AutoScalingGroup } from "./constructs/autoscaling-group";
import { ZabbixServer } from "./constructs/zabbix-server";

export class AsgStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    const zoneName = "corp.non-97.net";

    // VPC
    const vpc = new Vpc(this, "Vpc");

    // Route 53
    const route53 = new Route53(this, "Route53", {
      vpc: vpc.vpc,
      zoneName,
    });

    // Zabbix Server
    const zabbixServer = new ZabbixServer(this, "ZabbixServer", {
      vpc: vpc.vpc,
    });

    // Auto Scaling
    const asg = new AutoScalingGroup(this, "Asg", {
      vpc: vpc.vpc,
      hostedZone: route53.hostedZone,
      zabbixServerIpAddress: zabbixServer.instance.instancePrivateIp,
    });

    asg.asg.connections.allowFrom(
      zabbixServer.instance.connections,
      cdk.aws_ec2.Port.tcp(10050)
    );

    zabbixServer.instance.connections.allowFrom(
      asg.asg.connections,
      cdk.aws_ec2.Port.tcp(10051)
    );
  }
}
