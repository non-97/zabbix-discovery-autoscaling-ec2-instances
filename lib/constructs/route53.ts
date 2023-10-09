import * as cdk from "aws-cdk-lib";
import { Construct } from "constructs";

export interface Route53Props {
  vpc: cdk.aws_ec2.IVpc;
  zoneName: string;
}

export class Route53 extends Construct {
  readonly hostedZone: cdk.aws_route53.PrivateHostedZone;

  constructor(scope: Construct, id: string, props: Route53Props) {
    super(scope, id);

    this.hostedZone = new cdk.aws_route53.PrivateHostedZone(this, "Default", {
      vpc: props.vpc,
      zoneName: props.zoneName,
    });
  }
}
