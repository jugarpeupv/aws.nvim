# Changelog

## 1.0.0 (2026-04-16)


### Features

* add support for aws acm ([736371d](https://github.com/jugarpeupv/aws.nvim/commit/736371d605f1cba82956e3617058568b9a1bd7a3))
* **apigateway:** add API Gateway REST API support ([bf85256](https://github.com/jugarpeupv/aws.nvim/commit/bf852561c63e797bc8d102f4052ffa2f440862b3))
* **cloudformation:** add resources tree buffer ([3ba3882](https://github.com/jugarpeupv/aws.nvim/commit/3ba3882177360661aac8bb2fedef4fb56b859b6f))
* **cloudfront:** add CloudFront support with list, detail, and invalidate ([7450231](https://github.com/jugarpeupv/aws.nvim/commit/745023111a564a686622155b57d093b2f86c7418))
* correct s3 buffer highlights and prepare pipelines ([5461091](https://github.com/jugarpeupv/aws.nvim/commit/54610915aeabb800d6448c0b7b16ed1c21815b8f))
* **docs:** update keymaps and add user guide ([f8f7f28](https://github.com/jugarpeupv/aws.nvim/commit/f8f7f28235d48ad6e908cae9db492be2c5e5d939))
* **dynamodb:** add DynamoDB table explorer and commands ([9ec4921](https://github.com/jugarpeupv/aws.nvim/commit/9ec4921ef96b09cb205992b8ff6b701ad8d7e7d0))
* **dynamodb:** refactor scan/query UI to AWS console style ([d135fae](https://github.com/jugarpeupv/aws.nvim/commit/d135fae1421f5a0097bbb298d84631c5284610e5))
* **ec2:** add EC2 instance list and detail views ([9d58f24](https://github.com/jugarpeupv/aws.nvim/commit/9d58f24df693bc5810744884ad30823dbeb00194))
* **ecs:** add ECS/Fargate support and service picker ([6f47b64](https://github.com/jugarpeupv/aws.nvim/commit/6f47b64b64ad99284eba61f0aa72cf09dc096789))
* **iam:** add IAM service support and UI ([e494d5d](https://github.com/jugarpeupv/aws.nvim/commit/e494d5d9639025f35f0d8a5556a1952e1edb6d65))
* Initial working commit ([c707871](https://github.com/jugarpeupv/aws.nvim/commit/c707871923abadd73bc213d9c3c6ba81da4c15ff))
* **lambda:** add Lambda function management support ([1220bcd](https://github.com/jugarpeupv/aws.nvim/commit/1220bcd2848afd128e73893d47ae9ce8b6783626))
* **s3:** persist oil extra_s3_args per bucket buffer ([a4e4643](https://github.com/jugarpeupv/aws.nvim/commit/a4e4643866ffa67ed329f904be1a3335bfc5041c))
* **secretsmanager:** add Secrets Manager support ([586ead4](https://github.com/jugarpeupv/aws.nvim/commit/586ead4909bc8f468a6fd2de66183e3bb088263d))
* show region/profile in buffer titles and add S3 oil open ([b2b2d20](https://github.com/jugarpeupv/aws.nvim/commit/b2b2d20462ccbf3ef5e38fd529efb3b8239b2ac8))
* update readme to include supported aws services ([31963c5](https://github.com/jugarpeupv/aws.nvim/commit/31963c5cdc688374d6826ac5e69c655d935b41ac))
* **vpc:** add VPC explorer with subnets, gateways, routes, SGs ([837b845](https://github.com/jugarpeupv/aws.nvim/commit/837b845774abdfc0fa52e4ee6dc5c33f7afb9080))


### Bug Fixes

* **cloudformation:** handle non-string event fields safely ([d4aeea9](https://github.com/jugarpeupv/aws.nvim/commit/d4aeea999730fbae2ed95d720a4e4985a6240d1d))
* Update proper installation instructions ([406f656](https://github.com/jugarpeupv/aws.nvim/commit/406f656e006de12e156d02e42b1847c371038740))
