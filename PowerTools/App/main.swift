import Darwin

if CommandLine.arguments.contains(TransformHelper.argument) {
    Darwin.exit(TransformHelper.run())
}

if CommandLine.arguments.contains(RuleMatchHelper.argument) {
    Darwin.exit(RuleMatchHelper.run())
}

PowerToolsApp.main()
