// 冒烟测试：应用可以正常构建出根组件。
// 具体业务流程（书库、解析器、同步）由 tool/ 下的离线脚本覆盖。

import 'package:flutter_test/flutter_test.dart';

import 'package:novel_reader/main.dart';

void main() {
  testWidgets('app builds without exceptions', (WidgetTester tester) async {
    await tester.pumpWidget(const DanQingReaderApp());
    expect(find.byType(DanQingReaderApp), findsOneWidget);
  });
}
