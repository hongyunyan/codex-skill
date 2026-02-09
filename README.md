Review 他人/自己代码
review https://github.com/pingcap/ticdc/pull/3803

分析 CI 上失败的 case
ci-diagnose fix(*): merge operator inconsistent after maintainer move by wlwilliamx · Pull Request #3769 · pingc <--job pull-cdc-mysql-integration-heavy --groups group1,group3>

根据设计文档开发
dev-with-doc xxx.md <--desc "一句话描述要做什么（可空）”>

review 自己的代码
review-self <rfc-xxx.md>

根据方案写 design doc
write-design-doc ci-diagnose

根据方案生成 design doc，做开发，并且 review
ship-with-doc <feature-slug> --title "设计文档标题" --desc "一句话描述这次要实现什么（可选）"
