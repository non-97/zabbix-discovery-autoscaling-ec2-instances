import * as cdk from "aws-cdk-lib";
import { Construct } from "constructs";
import * as fs from "fs";
import * as path from "path";

export interface AutoScalingGroupProps {
  vpc: cdk.aws_ec2.IVpc;
}

export class AutoScalingGroup extends Construct {
  readonly asg: cdk.aws_autoscaling.AutoScalingGroup;

  constructor(scope: Construct, id: string, props: AutoScalingGroupProps) {
    super(scope, id);

    const autoScalingGroupName = "asg";

    // IAM Role
    const role = new cdk.aws_iam.Role(this, "Role", {
      assumedBy: new cdk.aws_iam.ServicePrincipal("ec2.amazonaws.com"),
      managedPolicies: [
        new cdk.aws_iam.ManagedPolicy(this, "Policy", {
          statements: [
            new cdk.aws_iam.PolicyStatement({
              effect: cdk.aws_iam.Effect.ALLOW,
              resources: ["*"],
              actions: ["ec2:DescribeInstances", "ec2:DescribeTags"],
            }),
            new cdk.aws_iam.PolicyStatement({
              effect: cdk.aws_iam.Effect.ALLOW,
              resources: ["*"],
              actions: ["ec2:CreateTags", "ec2:DeleteTags"],
              conditions: {
                StringEquals: {
                  "aws:ResourceTag/aws:autoscaling:groupName":
                    autoScalingGroupName,
                },
              },
            }),
          ],
        }),
      ],
    });

    // User data
    const userDataScript = fs.readFileSync(
      path.join(__dirname, "../ec2/user-data.sh"),
      "utf8"
    );
    const userData = cdk.aws_ec2.UserData.forLinux();
    userData.addCommands(userDataScript);

    this.asg = new cdk.aws_autoscaling.AutoScalingGroup(this, "Default", {
      autoScalingGroupName,
      machineImage: cdk.aws_ec2.MachineImage.latestAmazonLinux2023({
        cachedInContext: true,
      }),
      instanceType: new cdk.aws_ec2.InstanceType("t3.nano"),
      vpc: props.vpc,
      vpcSubnets: props.vpc.selectSubnets({
        subnetGroupName: "Public",
      }),
      maxCapacity: 10,
      minCapacity: 10,
      role,
      ssmSessionPermissions: true,
      userData,
      healthCheck: cdk.aws_autoscaling.HealthCheck.elb({
        grace: cdk.Duration.minutes(3),
      }),
    });
    this.asg.scaleOnCpuUtilization("CpuScaling", {
      targetUtilizationPercent: 50,
    });
  }
}
