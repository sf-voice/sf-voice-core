//! CloudFormation Quick Create Stack support — generates the one-click
//! URL that opens AWS Console prefilled with our template + parameters,
//! and serves the YAML template at /cfn/sf-voice-readonly.yaml.
//!
//! customer flow:
//!   1. our app POSTs the bucket name + region; gets an external_id.
//!   2. customer clicks "set up via AWS console" → opens the URL below.
//!   3. AWS Console pre-fills the stack form. customer reviews + creates.
//!   4. customer copies the Role ARN from CloudFormation Outputs.
//!   5. customer pastes Role ARN back into our app.
//!
//! Quick-create URL doc:
//! https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/cfn-quickcreate-links.html

use urlencoding::encode;

/// the trust principal for sf-voice's prod AWS account. customers grant
/// this principal AssumeRole rights via the trust policy in our cfn
/// template. real value belongs in env; dev placeholder is fine because
/// no one's actually deploying yet.
pub fn our_aws_principal() -> String {
    std::env::var("SF_VOICE_AWS_PRINCIPAL")
        .unwrap_or_else(|_| "arn:aws:iam::000000000000:root".to_string())
}

/// public URL where the CFN template YAML is hosted. AWS Console must
/// be able to fetch it, so this MUST be a publicly reachable HTTPS URL
/// in prod. dev falls back to the api host but AWS console can't reach
/// localhost — see the frontend's "copy template manually" fallback.
pub fn template_url() -> String {
    std::env::var("SF_VOICE_CFN_TEMPLATE_URL")
        .unwrap_or_else(|_| "https://app.sf-voice.sh/cfn/sf-voice-readonly.yaml".to_string())
}

/// the full CFN YAML. shipped as a Rust const so a fresh checkout has
/// no extra setup. when we want this hosted (prod), upload this exact
/// string to s3/cloudfront and set `SF_VOICE_CFN_TEMPLATE_URL`.
pub const TEMPLATE_YAML: &str = r#"AWSTemplateFormatVersion: '2010-09-09'
Description: >
  sf-voice — read-only role for ingesting call recordings from a single
  S3 bucket prefix. sf-voice assumes this role with an external id we
  generate per-org; no long-lived secrets leave your account.

Parameters:
  ExternalId:
    Type: String
    Description: External id provided by sf-voice. Required.
  BucketName:
    Type: String
    Description: Name of the S3 bucket that holds call recordings.
  BucketPrefix:
    Type: String
    Default: ''
    Description: Optional prefix inside the bucket (e.g. calls/2026/).
  SfVoicePrincipal:
    Type: String
    Description: The IAM principal that sf-voice will use to assume this role.

Resources:
  SfVoiceReadRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: !Sub 'sf-voice-readonly-${AWS::StackName}'
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              AWS: !Ref SfVoicePrincipal
            Action: sts:AssumeRole
            Condition:
              StringEquals:
                sts:ExternalId: !Ref ExternalId
      Policies:
        - PolicyName: SfVoiceBucketRead
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action:
                  - s3:GetObject
                Resource: !Sub 'arn:aws:s3:::${BucketName}/${BucketPrefix}*'
              - Effect: Allow
                Action:
                  - s3:ListBucket
                  - s3:GetBucketLocation
                Resource: !Sub 'arn:aws:s3:::${BucketName}'
                Condition:
                  StringLike:
                    s3:prefix:
                      - !Sub '${BucketPrefix}*'

Outputs:
  RoleArn:
    Description: Paste this back into sf-voice's "Connect AWS" page.
    Value: !GetAtt SfVoiceReadRole.Arn
"#;

/// build a Quick Create Stack URL prefilled with bucket info + the
/// external id. region defaults to us-east-1 if the customer hasn't
/// picked one yet — they can change it in the console.
pub fn quick_create_url(
    region: &str,
    external_id: &str,
    bucket_name: &str,
    bucket_prefix: &str,
) -> String {
    let template = template_url();
    let principal = our_aws_principal();
    let stack_name = "sf-voice-readonly";

    format!(
        "https://console.aws.amazon.com/cloudformation/home?region={region}#/stacks/quickcreate?\
         templateURL={template}\
         &stackName={stack}\
         &param_ExternalId={external}\
         &param_BucketName={bucket}\
         &param_BucketPrefix={prefix}\
         &param_SfVoicePrincipal={principal}",
        region = encode(region),
        template = encode(&template),
        stack = encode(stack_name),
        external = encode(external_id),
        bucket = encode(bucket_name),
        prefix = encode(bucket_prefix),
        principal = encode(&principal),
    )
}
