import * as cdk from "aws-cdk-lib";
import { Construct } from "constructs";
import { Vpc } from "./constructs/vpc";
import { AutoScalingGroup } from "./constructs/autoscaling-group";

export class AsgStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // VPC
    const vpc = new Vpc(this, "Vpc");

    // EC2 Instance
    new AutoScalingGroup(this, "Asg", {
      vpc: vpc.vpc,
    });
  }
}
