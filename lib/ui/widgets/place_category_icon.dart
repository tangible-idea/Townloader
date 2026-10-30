import 'package:flutter/material.dart';

/// 카카오맵 업종 이름(예: `카페`, `디저트카페`, `호프,요리주점`, `KTX정차역`)에 맞는 아이콘.
///
/// 업종 이름은 자유로운 한국어라서 낱말이 들어 있는지로 고른다. 위쪽 규칙이 이긴다
/// (`디저트카페` 는 카페보다 디저트, `와인바` 는 술집보다 와인). 맞는 것이 없으면 null.
IconData? placeCategoryIcon(String? category) {
  final name = category?.replaceAll(' ', '');
  if (name == null || name.isEmpty) return null;
  for (final (words, icon) in _rules) {
    if (words.any(name.contains)) return icon;
  }
  return _exact[name] ?? (name.endsWith('바') ? Icons.local_bar_outlined : null);
}

/// 다른 낱말 속에 섞여 엉뚱하게 걸리기 쉬운 짧은 이름은 통째로 같을 때만 쓴다.
const _exact = <String, IconData>{
  '회': Icons.set_meal_outlined,
  '죽': Icons.rice_bowl_outlined,
  '산': Icons.terrain_outlined,
  '절': Icons.temple_buddhist_outlined,
  '역': Icons.train_outlined,
  '옷': Icons.shopping_bag_outlined,
  '궁': Icons.castle_outlined,
};

const List<(List<String>, IconData)> _rules = [
  // ── 디저트·카페 ──
  (['베이커리', '제과', '빵', '도넛', '베이글'], Icons.bakery_dining_outlined),
  (['아이스크림', '빙수', '젤라또'], Icons.icecream_outlined),
  (['디저트', '케이크', '떡', '마카롱', '초콜릿'], Icons.cake_outlined),
  (['브런치'], Icons.brunch_dining_outlined),
  (['북카페'], Icons.menu_book_outlined),
  (['키즈카페', '놀이방'], Icons.child_care_outlined),
  (['카페', '커피', '찻집', '전통차', '티하우스'], Icons.local_cafe_outlined),

  // ── 술 ──
  (['와인'], Icons.wine_bar_outlined),
  (['호프', '맥주', '펍', '브루어리'], Icons.sports_bar_outlined),
  (
    ['술집', '주점', '이자카야', '포차', '포장마차', '칵테일', '위스키', '막걸리'],
    Icons.local_bar_outlined,
  ),

  // ── 음식점 ──
  (['피자'], Icons.local_pizza_outlined),
  (['햄버거', '버거', '샌드위치', '패스트푸드'], Icons.lunch_dining_outlined),
  (['치킨', '닭', '꼬치', '케밥'], Icons.kebab_dining_outlined),
  (
    [
      '고기', '구이', '갈비', '삼겹살', '곱창', '막창', '족발', '보쌈', //
      '스테이크', '바베큐', '바비큐', '육류',
    ],
    Icons.outdoor_grill_outlined,
  ),
  (
    [
      '국수', '라면', '라멘', '우동', '냉면', '소바', '쌀국수', '짬뽕', //
      '중식', '중국요리', '마라', '칼국수',
    ],
    Icons.ramen_dining_outlined,
  ),
  (
    [
      '일식', '초밥', '스시', '오마카세', '횟집', '해산물', '해물', '생선', //
      '조개', '장어', '복어', '수산',
    ],
    Icons.set_meal_outlined,
  ),
  (['양식', '이탈리안', '파스타', '프랑스', '스페인', '레스토랑'], Icons.dinner_dining_outlined),
  (['샐러드', '비건', '채식'], Icons.eco_outlined),
  (
    [
      '한식', '백반', '국밥', '분식', '덮밥', '찌개', '한정식', '도시락', //
      '아시아', '태국', '베트남', '인도',
    ],
    Icons.rice_bowl_outlined,
  ),
  (['음식', '식당', '요리', '맛집', '뷔페'], Icons.restaurant_outlined),

  // ── 숙소 ──
  (['펜션', '캠핑', '글램핑', '한옥', '민박', '풀빌라'], Icons.cabin_outlined),
  (['호텔', '모텔', '숙박', '리조트', '게스트하우스', '스테이'], Icons.hotel_outlined),

  // 둘레길은 `남한산성둘레길` 처럼 유적 이름이 붙어도 걷는 길이다.
  (['둘레길', '산책로', '등산로', '트레킹', '올레'], Icons.hiking_outlined),

  // ── 종교·유적 ──
  (['교회', '성당'], Icons.church_outlined),
  (['사찰', '사원', '종교', '성지'], Icons.temple_buddhist_outlined),
  (
    ['유적', '사적', '문화재', '고궁', '궁궐', '성곽', '산성', '향교', '서원'],
    Icons.castle_outlined,
  ),

  // ── 자연 ──
  (['꽃집', '플라워'], Icons.local_florist_outlined),
  (['공원', '정원', '수목원', '식물원', '숲', '꽃'], Icons.park_outlined),
  (['해수욕장', '해변', '바다', '해안', '섬'], Icons.beach_access_outlined),
  (['호수', '저수지', '하천', '강변', '폭포'], Icons.water_outlined),
  (['등산', '계곡', '오름', '봉우리', '산림', '자연'], Icons.terrain_outlined),
  (['동물원', '아쿠아리움', '수족관', '목장'], Icons.pets_outlined),

  // ── 볼거리·놀거리 ──
  (['박물관', '미술관', '갤러리', '전시', '기념관', '문화'], Icons.museum_outlined),
  (['서점', '책방', '도서관'], Icons.menu_book_outlined),
  (['영화', '극장', '공연', '콘서트'], Icons.theaters_outlined),
  (['스파', '사우나', '찜질', '온천'], Icons.spa_outlined),
  (['공방', '체험', '클래스'], Icons.palette_outlined),
  (['사진', '포토', '스튜디오'], Icons.photo_camera_outlined),
  (
    ['테마파크', '놀이', '관광', '명소', '전망대', '랜드마크', '거리', '마을', '민속촌'],
    Icons.attractions_outlined,
  ),

  // ── 운동 ──
  (['골프'], Icons.golf_course_outlined),
  (['수영'], Icons.pool_outlined),
  (
    ['체육', '운동장', '경기장', '헬스', '스포츠', '피트니스', '클라이밍'],
    Icons.fitness_center_outlined,
  ),

  // ── 교통 ──
  (['지하철', '전철', '출구'], Icons.subway_outlined),
  (['정차역', '기차', '철도', 'KTX', 'SRT'], Icons.train_outlined),
  (['버스', '터미널'], Icons.directions_bus_outlined),
  (['공항'], Icons.flight_outlined),
  (['항구', '여객', '선착장', '페리'], Icons.directions_boat_outlined),
  (['주차'], Icons.local_parking_outlined),
  (['주유', '충전소'], Icons.local_gas_station_outlined),

  // ── 쇼핑 ──
  (
    ['편의점', '이마트24', 'GS25', 'CU', '세븐일레븐', '미니스톱'],
    Icons.local_convenience_store_outlined,
  ),
  (['식품', '슈퍼', '마트', '정육', '반찬', '농산물'], Icons.local_grocery_store_outlined),
  (
    ['시장', '백화점', '쇼핑', '아울렛', '소품', '편집숍', '의류', '잡화', '문구'],
    Icons.shopping_bag_outlined,
  ),

  // ── 의료·공공 ──
  (['약국'], Icons.local_pharmacy_outlined),
  (['병원', '의원', '보건', '치과', '한의원', '의료'], Icons.local_hospital_outlined),
  (['경찰', '지구대', '파출소'], Icons.local_police_outlined),
  (['소방', '119'], Icons.local_fire_department_outlined),
  (['장례', '화장터', '추모', '납골', '묘지', '봉안'], Icons.local_florist_outlined),
  (
    ['시청', '구청', '군청', '도청', '주민센터', '행정', '공공', '관리위원회', '행정복지', '우체국', '청사'],
    Icons.account_balance_outlined,
  ),
  (['복지', '요양', '노인', '경로당', '어린이집'], Icons.volunteer_activism_outlined),
  (['학교', '학원', '대학', '교육'], Icons.school_outlined),
  (['은행', '금융', 'ATM'], Icons.account_balance_wallet_outlined),
  (['기업', '회사', '사무소', '인력', '직업'], Icons.business_outlined),
];
