import logging

from drf_spectacular.utils import extend_schema, OpenApiParameter
from rest_framework import status
from rest_framework.generics import ListAPIView
from rest_framework.permissions import AllowAny
from rest_framework.response import Response

from apps.common import models
from apps.common.middleware.logging_middleware import get_correlation_id
from . import serializers

logger = logging.getLogger("apps.common.frontend_translations")


class FrontendTranslationView(ListAPIView):
    serializer_class = serializers.FrontendTranslationSerializer
    permission_classes = (AllowAny,)

    @extend_schema(
        parameters=[
            OpenApiParameter(
                name="key",
                type=str,
                location=OpenApiParameter.QUERY,
                description="Key",
            )
        ]
    )
    def get(self, request):
        corr_id = get_correlation_id()
        key = request.GET.get("key")

        logger.info(
            "Fetching frontend translations",
            extra={
                "correlation_id": corr_id,
                "filter_key": key,
                "user_id": str(request.user) if request.user.is_authenticated else None,
            }
        )

        serializer = self.get_serializer(self.get_queryset(), many=True)
        data = {}
        for obj in serializer.data:
            data[obj["key"]] = obj["text"]

        logger.info(
            "Frontend translations fetched",
            extra={
                "correlation_id": corr_id,
                "translation_count": len(data),
            }
        )

        return Response(data, status=status.HTTP_200_OK)

    def get_queryset(self):
        queryset = models.FrontendTranslation.objects.all()
        key = self.request.GET.get("key", None)

        if key:
            queryset = queryset.filter(key__icontains=key)

        return queryset
