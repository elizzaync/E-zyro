-- Migración: carta_garantia — agregar URLs de firmas y documento PDF
-- Fecha: 2026-06-07
-- Propósito: persistir las firmas en Cloudinary y referenciar el PDF futuro

ALTER TABLE carta_garantia
  ADD COLUMN IF NOT EXISTS firma_verificador_url TEXT,
  ADD COLUMN IF NOT EXISTS firma_gerente_url     TEXT,
  ADD COLUMN IF NOT EXISTS documento_pdf_url     TEXT;

COMMENT ON COLUMN carta_garantia.firma_verificador_url IS 'URL Cloudinary de la firma del verificador (Ing. Guerrero)';
COMMENT ON COLUMN carta_garantia.firma_gerente_url     IS 'URL Cloudinary de la firma del gerente general (Ing. Galindo)';
COMMENT ON COLUMN carta_garantia.documento_pdf_url     IS 'URL Cloudinary del PDF generado (futuro módulo Panel Cliente)';
