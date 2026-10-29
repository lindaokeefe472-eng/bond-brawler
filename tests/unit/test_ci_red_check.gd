## 临时用例：只为验证 CI 门禁会变红，验证完立刻删除。
extends GdUnitTestSuite

func test_this_must_fail() -> void:
	assert_int(1).is_equal(2)
