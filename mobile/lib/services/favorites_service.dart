// 즐겨찾기 저장소 서비스.
//
// 두 가지 네임스페이스를 한 클래스에서 관리합니다.
// 1) 프로젝트 즐겨찾기 (key: 'favorite_projects')
//    - 보고 상세 화면의 ★ 토글
// 2) 사업부 즐겨찾기 (key: 'favorite_divisions')
//    - 홈의 DivisionGridCard 우측 상단 ★ 토글
//
// 백엔드에 즐겨찾기 필드가 생기면 이 클래스만 교체하면 됩니다.

import 'package:shared_preferences/shared_preferences.dart';

class FavoritesService {
  // ============================================================
  // 프로젝트 즐겨찾기
  // ============================================================
  static const String _key = 'favorite_projects';

  // 프로젝트 즐겨찾기 전체를 Set 으로 반환.
  static Future<Set<String>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? const <String>[];
    return list.toSet();
  }

  // 특정 project_key 가 즐겨찾기되어 있는지.
  static Future<bool> isFavorite(String projectKey) async {
    final all = await loadAll();
    return all.contains(projectKey);
  }

  // 프로젝트 즐겨찾기 토글.
  // 반환값은 토글 직후 상태(true=즐겨찾기됨).
  static Future<bool> toggle(String projectKey) async {
    final prefs = await SharedPreferences.getInstance();
    final list = (prefs.getStringList(_key) ?? const <String>[]).toList();
    bool nowFavorite;

    if (list.contains(projectKey)) {
      list.remove(projectKey);
      nowFavorite = false;
    } else {
      list.add(projectKey);
      nowFavorite = true;
    }

    await prefs.setStringList(_key, list);
    return nowFavorite;
  }

  // 추가된 순서 그대로 List 반환.
  // 즐겨찾기 표시 순서가 매번 바뀌지 않도록 하기 위함.
  static Future<List<String>> loadAllAsList() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key) ?? const <String>[]).toList();
  }

  // ============================================================
  // 사업부 즐겨찾기 (Section: division favorites v1)
  // - 프로젝트 즐겨찾기와 키 네임스페이스 분리
  // - 시안의 DivisionGridCard 우측 상단 ★ 토글에 사용
  // ============================================================
  static const String _divKey = 'favorite_divisions';

  // 즐겨찾기된 사업부 id 들을 Set 으로 반환.
  static Future<Set<String>> loadAllDivisions() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_divKey) ?? const <String>[];
    return list.toSet();
  }

  // 특정 사업부가 즐겨찾기되어 있는지.
  static Future<bool> isDivisionFavorite(String divisionId) async {
    final all = await loadAllDivisions();
    return all.contains(divisionId);
  }

  // 사업부 즐겨찾기 토글.
  // 반환값은 토글 직후 상태(true=즐겨찾기됨).
  static Future<bool> toggleDivision(String divisionId) async {
    final prefs = await SharedPreferences.getInstance();
    final list =
        (prefs.getStringList(_divKey) ?? const <String>[]).toList();
    bool nowFavorite;

    if (list.contains(divisionId)) {
      list.remove(divisionId);
      nowFavorite = false;
    } else {
      list.add(divisionId);
      nowFavorite = true;
    }

    await prefs.setStringList(_divKey, list);
    return nowFavorite;
  }

  // 추가된 순서대로 List 반환.
  // 시안에서 즐겨찾기 카드 표시 순서 안정화 용도.
  static Future<List<String>> loadAllDivisionsAsList() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_divKey) ?? const <String>[]).toList();
  }
}