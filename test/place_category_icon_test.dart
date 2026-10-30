import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:townloader/ui/widgets/place_category_icon.dart';

void main() {
  test('카카오맵 업종 이름에 맞는 아이콘을 고른다', () {
    final cases = {
      '카페': Icons.local_cafe_outlined,
      '디저트카페': Icons.cake_outlined,
      '브런치카페': Icons.brunch_dining_outlined,
      '북카페': Icons.menu_book_outlined,
      '베이커리': Icons.bakery_dining_outlined,
      '와인바': Icons.wine_bar_outlined,
      '호프,요리주점': Icons.sports_bar_outlined,
      '칵테일바': Icons.local_bar_outlined,
      '바다': Icons.beach_access_outlined,
      '바베큐': Icons.outdoor_grill_outlined,
      '스테이크,립': Icons.outdoor_grill_outlined,
      '일본식라면': Icons.ramen_dining_outlined,
      '초밥,롤': Icons.set_meal_outlined,
      '이탈리안': Icons.dinner_dining_outlined,
      '한식': Icons.rice_bowl_outlined,
      '호텔': Icons.hotel_outlined,
      '미술관': Icons.museum_outlined,
      '공원': Icons.park_outlined,
      // 링크 화면에서 실제로 본 업종들.
      '도시근린공원': Icons.park_outlined,
      '공원시설물': Icons.park_outlined,
      '산': Icons.terrain_outlined,
      '남한산성둘레길': Icons.hiking_outlined,
      '교회': Icons.church_outlined,
      '절,사찰': Icons.temple_buddhist_outlined,
      '종교유적지': Icons.temple_buddhist_outlined,
      '문화유적': Icons.castle_outlined,
      '족발,보쌈': Icons.outdoor_grill_outlined,
      'KTX정차역': Icons.train_outlined,
      '지하철출구': Icons.subway_outlined,
      '이마트24': Icons.local_convenience_store_outlined,
      '식품판매': Icons.local_grocery_store_outlined,
      '체육관': Icons.fitness_center_outlined,
      '보건소': Icons.local_hospital_outlined,
      '경찰서': Icons.local_police_outlined,
      '소방서': Icons.local_fire_department_outlined,
      '시청': Icons.account_balance_outlined,
      '선거관리위원회': Icons.account_balance_outlined,
      '행정복지센터': Icons.account_balance_outlined,
      '노인복지시설': Icons.volunteer_activism_outlined,
      '장애인복지시설': Icons.volunteer_activism_outlined,
      '장례식장': Icons.local_florist_outlined,
      '화장터': Icons.local_florist_outlined,
      '직업소개,인력파견': Icons.business_outlined,
    };
    for (final MapEntry(key: name, value: icon) in cases.entries) {
      expect(placeCategoryIcon(name), icon, reason: name);
    }
  });

  test('업종을 모르면 null', () {
    expect(placeCategoryIcon(null), isNull);
    expect(placeCategoryIcon(''), isNull);
    expect(placeCategoryIcon('세무사'), isNull);
  });
}
