local _, addon = ...

local locale = type(GetLocale) == "function" and GetLocale() or "enUS"

local overrides = {
    frFR = {
        ANCHOR_FRAME = "Cadre d’ancrage :",
        MANUAL_FRAME = "Cadre manuel :",
        ITEM_SPELL_BAR = "Barre d’objets/sorts",
    },
    deDE = {
        GENERAL = "Allgemein", GENERAL_SETTINGS = "Allgemeine Einstellungen", PROFILES_ACTIONS = "Profile und Aktionen",
        APPEARANCE = "Aussehen", POSITIONING = "Positionierung", ANCHORING = "Verankerung", FREE_POSITION = "Freie Position",
        SHOW_MINIMAP_BUTTON = "Minikartenschaltfläche anzeigen", MINIMAP_ANGLE = "Winkel der Minikartenschaltfläche",
        ANCHORED = "Verankert", ANCHOR_FRAME = "Ankerrahmen:", POINT = "Punkt:", RELATIVE_POINT = "Relativer Punkt:",
        INHERIT_WIDTH = "Breite des Ankers übernehmen", LEFT_OFFSET = "Linker Innenabstand", RIGHT_OFFSET = "Rechter Innenabstand",
        RESET_POSITION = "Freie Position zurücksetzen", CLEAR_DAMAGE = "Erfassten Schaden löschen",
    },
    esES = {
        GENERAL = "General", GENERAL_SETTINGS = "Ajustes generales", PROFILES_ACTIONS = "Perfiles y acciones",
        APPEARANCE = "Apariencia", POSITIONING = "Posicionamiento", ANCHORING = "Anclaje", FREE_POSITION = "Posición libre",
        SHOW_MINIMAP_BUTTON = "Mostrar botón del minimapa", MINIMAP_ANGLE = "Ángulo del botón del minimapa",
        ANCHORED = "Anclado", ANCHOR_FRAME = "Marco de anclaje:", POINT = "Punto:", RELATIVE_POINT = "Punto relativo:",
        INHERIT_WIDTH = "Heredar ancho del anclaje", LEFT_OFFSET = "Margen izquierdo", RIGHT_OFFSET = "Margen derecho",
        RESET_POSITION = "Restablecer posición libre", CLEAR_DAMAGE = "Borrar daño registrado",
    },
    itIT = {
        ADDON_TITLE = "Lafee Damage Type Tracker", GENERAL = "Generale", GENERAL_SETTINGS = "Impostazioni generali",
        PROFILES_ACTIONS = "Profili e azioni", APPEARANCE = "Aspetto", POSITIONING = "Posizionamento", ANCHORING = "Ancoraggio",
        FREE_POSITION = "Posizione libera", ACTIVE_CHARACTER = "Personaggio attivo:", SHOW_BAR = "Mostra barra",
        SHOW_MINIMAP_BUTTON = "Mostra pulsante minimappa", MINIMAP_ANGLE = "Angolo pulsante minimappa", ANCHOR_MODE = "Modalità ancoraggio:",
        FREE = "Libero", ANCHORED = "Ancorato", ANCHOR_FRAME = "Riquadro di ancoraggio:", POINT = "Punto:", RELATIVE_POINT = "Punto relativo:",
        INHERIT_WIDTH = "Eredita larghezza dell’ancora", STYLE = "Stile:", CLASSIC = "Classico", SQUARE = "Quadrato",
        POSITION = "Posizione:", ABOVE = "Sopra", BELOW = "Sotto", MANUAL_FRAME = "Riquadro manuale:", OFFSET_X = "Offset X:", OFFSET_Y = "Offset Y:",
        WIDTH = "Larghezza", HEIGHT = "Altezza", WINDOW_SECONDS = "Durata (s)", COPY_FROM = "Copia configurazione da:", COPY = "Copia",
        RESET_POSITION = "Reimposta posizione libera", CLEAR_DAMAGE = "Cancella danni registrati", CLOSE = "Chiudi", NO_OTHER_CHARACTER = "Nessun altro personaggio",
        TOOLTIP_LEFT_CLICK = "Clic sinistro: opzioni", TOOLTIP_RIGHT_CLICK = "Clic destro: mostra/nascondi", TOOLTIP_DRAG = "Trascina: sposta pulsante",
    },
    ptBR = {
        ADDON_TITLE = "Lafee Damage Type Tracker", GENERAL = "Geral", GENERAL_SETTINGS = "Configurações gerais",
        PROFILES_ACTIONS = "Perfis e ações", APPEARANCE = "Aparência", POSITIONING = "Posicionamento", ANCHORING = "Ancoragem",
        FREE_POSITION = "Posição livre", ACTIVE_CHARACTER = "Personagem ativo:", SHOW_BAR = "Mostrar barra",
        SHOW_MINIMAP_BUTTON = "Mostrar botão do minimapa", MINIMAP_ANGLE = "Ângulo do botão do minimapa", ANCHOR_MODE = "Modo de ancoragem:",
        FREE = "Livre", ANCHORED = "Ancorado", ANCHOR_FRAME = "Quadro de ancoragem:", POINT = "Ponto:", RELATIVE_POINT = "Ponto relativo:",
        INHERIT_WIDTH = "Herdar largura da âncora", STYLE = "Estilo:", CLASSIC = "Clássico", SQUARE = "Quadrado",
        POSITION = "Posição:", ABOVE = "Acima", BELOW = "Abaixo", MANUAL_FRAME = "Quadro manual:", OFFSET_X = "Deslocamento X:", OFFSET_Y = "Deslocamento Y:",
        WIDTH = "Largura", HEIGHT = "Altura", WINDOW_SECONDS = "Duração (s)", COPY_FROM = "Copiar configuração de:", COPY = "Copiar",
        RESET_POSITION = "Redefinir posição livre", CLEAR_DAMAGE = "Limpar dano registrado", CLOSE = "Fechar", NO_OTHER_CHARACTER = "Nenhum outro personagem",
        TOOLTIP_LEFT_CLICK = "Clique esquerdo: opções", TOOLTIP_RIGHT_CLICK = "Clique direito: mostrar/ocultar", TOOLTIP_DRAG = "Arrastar: mover botão",
    },
    ruRU = {
        ADDON_TITLE = "Lafee — типы урона", GENERAL = "Общие", GENERAL_SETTINGS = "Общие настройки", PROFILES_ACTIONS = "Профили и действия",
        APPEARANCE = "Внешний вид", POSITIONING = "Позиционирование", ANCHORING = "Привязка", FREE_POSITION = "Свободная позиция",
        ACTIVE_CHARACTER = "Активный персонаж:", SHOW_BAR = "Показывать полосу", SHOW_MINIMAP_BUTTON = "Показывать кнопку у миникарты",
        MINIMAP_ANGLE = "Угол кнопки у миникарты", ANCHOR_MODE = "Режим привязки:", FREE = "Свободно", ANCHORED = "Привязано",
        ANCHOR_FRAME = "Рамка привязки:", POINT = "Точка:", RELATIVE_POINT = "Относительная точка:", INHERIT_WIDTH = "Наследовать ширину якоря",
        STYLE = "Стиль:", CLASSIC = "Классический", SQUARE = "Квадратный", POSITION = "Позиция:", ABOVE = "Сверху", BELOW = "Снизу",
        MANUAL_FRAME = "Рамка вручную:", OFFSET_X = "Смещение X:", OFFSET_Y = "Смещение Y:", WIDTH = "Ширина", HEIGHT = "Высота",
        WINDOW_SECONDS = "Длительность (с)", COPY_FROM = "Копировать настройки из:", COPY = "Копировать", RESET_POSITION = "Сбросить свободную позицию",
        CLEAR_DAMAGE = "Очистить данные урона", CLOSE = "Закрыть", NO_OTHER_CHARACTER = "Нет других персонажей",
        TOOLTIP_LEFT_CLICK = "ЛКМ: настройки", TOOLTIP_RIGHT_CLICK = "ПКМ: показать/скрыть", TOOLTIP_DRAG = "Перетащить: переместить кнопку",
    },
    koKR = {
        ADDON_TITLE = "Lafee 피해 유형 추적기", GENERAL = "일반", GENERAL_SETTINGS = "일반 설정", PROFILES_ACTIONS = "프로필 및 작업",
        APPEARANCE = "외형", POSITIONING = "위치", ANCHORING = "앵커", FREE_POSITION = "자유 위치",
        ACTIVE_CHARACTER = "활성 캐릭터:", SHOW_BAR = "막대 표시", SHOW_MINIMAP_BUTTON = "미니맵 버튼 표시", MINIMAP_ANGLE = "미니맵 버튼 각도",
        ANCHOR_MODE = "앵커 모드:", FREE = "자유", ANCHORED = "고정", ANCHOR_FRAME = "앵커 프레임:", POINT = "지점:", RELATIVE_POINT = "상대 지점:",
        INHERIT_WIDTH = "앵커 너비 사용", STYLE = "스타일:", CLASSIC = "클래식", SQUARE = "사각형", POSITION = "위치:", ABOVE = "위", BELOW = "아래",
        MANUAL_FRAME = "수동 프레임:", OFFSET_X = "X 오프셋:", OFFSET_Y = "Y 오프셋:", WIDTH = "너비", HEIGHT = "높이", WINDOW_SECONDS = "지속시간 (초)",
        COPY_FROM = "설정 복사 대상:", COPY = "복사", RESET_POSITION = "자유 위치 초기화", CLEAR_DAMAGE = "추적 피해 초기화", CLOSE = "닫기",
        NO_OTHER_CHARACTER = "다른 캐릭터 없음", TOOLTIP_LEFT_CLICK = "왼쪽 클릭: 옵션", TOOLTIP_RIGHT_CLICK = "오른쪽 클릭: 표시/숨기기", TOOLTIP_DRAG = "드래그: 버튼 이동",
    },
    zhCN = {
        GENERAL = "常规", GENERAL_SETTINGS = "常规设置", PROFILES_ACTIONS = "配置与操作", APPEARANCE = "外观", POSITIONING = "定位", ANCHORING = "锚定",
        FREE_POSITION = "自由位置", SHOW_MINIMAP_BUTTON = "显示小地图按钮", MINIMAP_ANGLE = "小地图按钮角度", ANCHORED = "已锚定",
        ANCHOR_FRAME = "锚定框体：", POINT = "锚点：", RELATIVE_POINT = "相对锚点：", INHERIT_WIDTH = "继承锚点宽度",
        LEFT_OFFSET = "左侧内缩", RIGHT_OFFSET = "右侧内缩", RESET_POSITION = "重置自由位置", CLEAR_DAMAGE = "清除已记录伤害",
    },
    zhTW = {
        GENERAL = "一般", GENERAL_SETTINGS = "一般設定", PROFILES_ACTIONS = "設定檔與操作", APPEARANCE = "外觀", POSITIONING = "定位", ANCHORING = "錨定",
        FREE_POSITION = "自由位置", SHOW_MINIMAP_BUTTON = "顯示小地圖按鈕", MINIMAP_ANGLE = "小地圖按鈕角度", ANCHORED = "已錨定",
        ANCHOR_FRAME = "錨定框架：", POINT = "錨點：", RELATIVE_POINT = "相對錨點：", INHERIT_WIDTH = "沿用錨點寬度",
        LEFT_OFFSET = "左側內縮", RIGHT_OFFSET = "右側內縮", RESET_POSITION = "重設自由位置", CLEAR_DAMAGE = "清除已記錄傷害",
    },
}

overrides.esMX = overrides.esES

for key, value in pairs(overrides[locale] or {}) do
    addon.L[key] = value
end
