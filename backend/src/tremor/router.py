from datetime import datetime, timedelta

from fastapi import APIRouter, Depends
from sqlmodel import Session, select

from src.database import get_session
from src.users.models import User
from src.tremor.models import TremorReport, TremorReportCreate, TremorReportPublic
from src.auth.router import aktif_kullanici
from src.detect.router import tespit_et_ve_kaydet, erken_uyari_tetikle

router = APIRouter(
    prefix="/tremor-reports",
    tags=["Tremor Reports"],
)


@router.post("/", response_model=TremorReportPublic, summary="Yeni sarsinti raporu gonder")
def create_tremor_report(
    *,
    report: TremorReportCreate,
    session: Session = Depends(get_session),
    current_user: User = Depends(aktif_kullanici),
):
    esik = datetime.utcnow() - timedelta(seconds=60)
    son_rapor = session.exec(
        select(TremorReport)
        .where(
            TremorReport.user_id == current_user.id,
            TremorReport.reported_at >= esik,
        )
        .order_by(TremorReport.reported_at.desc())
    ).first()

    if son_rapor:
        son_rapor.intensity = report.intensity
        son_rapor.reported_at = datetime.utcnow()
        db_report = son_rapor
    else:
        db_report = TremorReport(**report.model_dump(), user_id=current_user.id)

    session.add(db_report)
    session.commit()
    session.refresh(db_report)
    # Mesafe bazli erken uyari (Asama 5): AGIR 5-dakikalik kesinlesmis-alarm sorgusundan
    # ONCE calisir — hiz bu katmanin tek amaci. TremorReport tablosunu sadece OKUR, bu
    # yuzden asagidaki tespit_et_ve_kaydet ile CAKISMAZ (sira onemli degil, once konularak
    # kendi gecikmesi minimumda tutuluyor).
    erken_uyari_tetikle(session)
    tespit_et_ve_kaydet(session)
    return db_report
